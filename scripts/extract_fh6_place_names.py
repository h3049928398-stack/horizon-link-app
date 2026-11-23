"""Read local FH6 string tables; export research artifacts without editing App assets.

Only Python's standard library is used. Source archives are opened read-only.
The observed STR v8 layout has two hash-indexed UTF-8 blocks: text and IDS keys.
"""

import argparse
import collections
import csv
import hashlib
import json
from pathlib import Path
import re
import struct
import unicodedata
import zipfile


def parse_str(data):
    if len(data) < 140 or data[:2] != b"\x00\x08":
        raise ValueError("Unsupported STR header")
    if struct.unpack_from("<H", data, 130)[0] != 2:
        raise ValueError("Expected two STR blocks")
    offsets = struct.unpack_from("<II", data, 132)
    if offsets[0] != 140:
        raise ValueError("Unexpected block offset")
    blocks = []
    for off, limit in zip(offsets, (*offsets[1:], len(data))):
        size, text_size, count = struct.unpack_from("<III", data, off)
        start = off + 12 + count * 8
        if size != count * 8 + text_size or off + 12 + size != limit:
            raise ValueError("STR block size mismatch")
        rows = {}
        for i in range(count):
            key_hash, rel = struct.unpack_from("<II", data, off + 12 + i * 8)
            if key_hash in rows or rel >= text_size:
                raise ValueError("Duplicate hash or invalid string offset")
            if rel and data[start + rel - 1] != 0:
                raise ValueError("Offset does not point to a string boundary")
            end = data.index(0, start + rel, limit)
            rows[key_hash] = data[start + rel:end].decode("utf-8", errors="strict")
        blocks.append(rows)
    values, keys = blocks
    if values.keys() != keys.keys() or len(set(keys.values())) != len(keys):
        raise ValueError("Text/IDS hash sets differ or IDS keys repeat")
    return {keys[h]: (f"{h:08x}", v) for h, v in values.items()}


# Tables and prefixes identify names, not all surrounding UI/descriptions.
# Their presence in a shipped archive does not prove an active map marker.
NAME_PREFIXES = {
    "Landmarks": ("IDS_Area_Discovered_",),
    "MapRegion": ("IDS_Name_", "IDS_ShortName_"),
    "PlayerHouse": ("IDS_DisplayName_",),
    "CareerTrackInfo": ("IDS_Name_", "IDS_DisplayName_"),
    "CareerRace": ("IDS_Name_",),
    "CareerRaceCollection": ("IDS_Name_",),
    "SpeedTrap": ("IDS_AmbientGameplayId_",),
    "SpeedZone": ("IDS_AmbientGameplayId_",),
    "DriftZone": ("IDS_AmbientGameplayId_",),
    "DangerSign": ("IDS_AmbientGameplayId_",),
    "Trailblazer": ("IDS_AmbientGameplayId_",),
    "DragEvent": ("IDS_DisplayName_", "IDS_AmbientGameplayId_"),
    "DriftAttack": ("IDS_DisplayName_", "IDS_AmbientGameplayId_"),
    "TimeAttack": ("IDS_DisplayName_",),
    "TimeTrial": ("IDS_DisplayName_", "IDS_AmbientGameplayId_"),
    "CarMeets": ("IDS_CarMeets_Interact_Line2_",),
}


def normalize(value):
    # Punctuation/whitespace only, no translation or fuzzy/coordinate matching.
    return re.sub(r"[\W_]+", "", unicodedata.normalize("NFKC", value).casefold())


def write_csv(path, rows, fields):
    with path.open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def extract(media, places_path, output):
    source = media / "Stripped" / "StringTables"
    places = json.loads(places_path.read_text(encoding="utf-8"))
    output.mkdir(parents=True, exist_ok=True)
    languages, audit = {}, {}
    for lang in ("CHS", "EN", "CHT"):
        path = source / (lang + ".zip")
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        with zipfile.ZipFile(path) as archive:
            if archive.testzip() is not None:
                raise ValueError(f"ZIP CRC check failed: {lang}")
            languages[lang] = {
                Path(name).stem: parse_str(archive.read(name))
                for name in archive.namelist() if name.endswith(".str")
            }
        # A second read detects source changes during extraction.
        if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise ValueError(f"Source changed during extraction: {lang}")
        audit[lang] = {
            "path": str(path), "sha256": digest,
            "tables": len(languages[lang]),
            "entries": sum(map(len, languages[lang].values())),
        }
    if not all(languages[x].keys() == languages["EN"].keys() for x in languages):
        raise ValueError("Language table sets differ")
    records, inventory = [], []
    for table, english in languages["EN"].items():
        chinese, traditional = languages["CHS"][table], languages["CHT"][table]
        if english.keys() != chinese.keys() or english.keys() != traditional.keys():
            raise ValueError(f"Language IDS sets differ: {table}")
        inventory.append({"table": table, "entries": len(english)})
        for key, (h, value) in english.items():
            if chinese[key][0] != h or traditional[key][0] != h:
                raise ValueError(f"Language hash mismatch: {table}/{key}")
            records.append({"table": table, "key": key, "hash": h,
                            "en": value, "zh_hans": chinese[key][1],
                            "zh_hant": traditional[key][1]})
    names = []
    for row in records:
        if row["key"].startswith(NAME_PREFIXES.get(row["table"], ())):
            row = dict(row)
            row["status"] = ("placeholder_or_test" if re.search(
                r"placeholder|\btest\b|\bbrio\b|\bgpl\b", row["en"], re.I)
                else "name_candidate_not_verified_ingame")
            names.append(row)
    index = collections.defaultdict(list)
    for row in records:
        if row["en"].strip():
            index[normalize(row["en"])].append(row)
    matches, matched_sources = [], {}
    for place in places:
        hits = index.get(normalize(place["name"]), [])
        translations = sorted({r["zh_hans"] for r in hits if r["zh_hans"].strip()})
        status = ("no_match" if not translations else "ambiguous_translation"
                  if len(translations) > 1 else "english_name_match_only")
        matches.append({"place_id": place["id"], "category": place["category"],
                        "name": place["name"], "status": status,
                        "zh_hans_candidates": translations, "sources": hits})
        for hit in hits:
            matched_sources[(hit["table"], hit["key"])] = hit
    fields = ["table", "key", "hash", "en", "zh_hans", "zh_hant"]
    write_csv(output / "name_candidates.csv", names, fields + ["status"])
    write_csv(output / "community_matched_strings.csv", matched_sources.values(), fields)
    write_csv(output / "landmarks.csv", [r for r in names if r["table"] == "Landmarks"], fields)
    write_csv(output / "community_matches.csv", [
        {**r, "zh_hans_candidates": " | ".join(r["zh_hans_candidates"]),
         "sources": " | ".join(x["table"] + "/" + x["key"] for x in r["sources"])}
        for r in matches], ["place_id", "category", "name", "status", "zh_hans_candidates", "sources"])
    report = {
        "source_archives": audit,
        "app_places_sha256": hashlib.sha256(places_path.read_bytes()).hexdigest(),
        "validation": "ZIP CRC; strict UTF-8; block bounds; unique hash/IDS; language key/hash equality; unchanged source hashes",
        "scope": "Research only. No App asset edits. Name matches do not verify coordinates or active game content. Unmatched names are not translated or guessed.",
        "candidate_counts": dict(collections.Counter(r["table"] for r in names)),
        "candidate_status": dict(collections.Counter(r["status"] for r in names)),
        "match_status": dict(collections.Counter(r["status"] for r in matches)),
        "match_by_category": {c: dict(collections.Counter(r["status"] for r in matches if r["category"] == c)) for c in sorted({r["category"] for r in matches})},
        "inventory": inventory, "name_candidates": names, "community_matches": matches,
    }
    (output / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    landmarks = [r for r in names if r["table"] == "Landmarks"]
    lines = [
        "# FH6 游戏内置地点中文名提取（研究结果）", "",
        "只读来源：本机游戏 media/Stripped/StringTables/{CHS,EN,CHT}.zip。",
        "三种语言按表名、IDS 键与哈希配对，未经机器翻译；原文空格和标点保留在 CSV/JSON 中。", "",
        "## 文件", "",
        "- landmarks.csv：Landmarks 表 75 条地标名称，含简体、繁体、英文和 IDS。",
        "- name_candidates.csv：指定地点/赛事相关表的 861 条名称候选；有重复名称，不能视为 861 个地点。",
        "- community_matches.csv：现有 965 条地图记录的名称匹配审计（含 170 个 Route 几何起点）。",
        "- community_matched_strings.csv：上述匹配命中的原始语言条目。",
        "- report.json：完整结果、分类计数、源 ZIP 哈希和结构校验说明。", "",
        "## 范围与限制", "",
        "语言包混有旧作遗留、测试及占位文本。候选筛选仅依据表名和 IDS 前缀；",
        "placeholder_or_test 只标记明显的测试词，其余候选也没有确认均在当前游戏中启用。",
        "75 条为地标名称表条目，不代表已经核实每条地图图钉和坐标。", "",
        "现有地图记录按英文名做 Unicode/标点/空白归一匹配：432 条只有一种中文文本，",
        "71 条有多个中文候选，462 条无匹配。匹配扫描所有语言表，可能命中 UI 或物品文本，",
        "english_name_match_only 不代表已确认同一游戏实体。没有按距离或模糊相似度自动关联。",
        "例：Tokyo Tower 同时命中‘东京塔’与‘#东京塔’，需要依据来源表判断。", "",
        "地标分类里 72/75 条英文名有匹配（其中 4 条中文有歧义）；未匹配的三条是",
        "Irokawa Space Centre、Kawazu Nandaru Loop Bridge、Festival Site Parking Lot。",
        "游戏表中分别存在 Irokawa Space Center（色川航天中心）和",
        "Kawazu Nanadaru Loop Bridge（河津七泷螺旋桥），但本轮未自动修正社区名称。", "",
        "广告牌、吉祥物、车房宝物、秘藏座驾等未必拥有逐个独立的地点名。",
        "广告牌 200 条和 Route 几何起点 170 条均未以当前名称直接匹配；不据此猜测官方命名。", "",
        "未修改 App 代码或 places.json，未安装手机版本，未进行游戏实车验证。", "",
        "## 地标名称（全部 75 条）", "",
        "| 英文原名 | 简体中文原名 |", "| --- | --- |",
    ]
    lines.extend(f"| {r['en'].strip()} | {r['zh_hans'].strip()} |" for r in landmarks)
    (output / "README.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps({k: report[k] for k in ("candidate_counts", "candidate_status", "match_status", "match_by_category")}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--media", type=Path, default=Path(r"D:\SteamLibrary\steamapps\common\ForzaHorizon6\media"))
    parser.add_argument("--places", type=Path, default=Path("flutter_app/assets/map/places.json"))
    parser.add_argument("--output", type=Path, default=Path("artifacts/place-names"))
    args = parser.parse_args()
    extract(args.media, args.places, args.output)
