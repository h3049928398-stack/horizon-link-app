from pathlib import Path
import struct

base=Path(r'D:\SteamLibrary\steamapps\common\ForzaHorizon6\media\OpenWorld\Brio')
for name in ['AITracks/Route101.nav','Freeroam/Brio_00.nav']:
    b=(base/name).read_bytes()
    n=struct.unpack_from('<I',b,88)[0]
    print('\nFILE',name,'HEADER',struct.unpack_from('<10I',b,88))
    for i in [0,1,2,n-2,n-1,n]:
        print('NODE',i,struct.unpack_from('<4I6f4H',b,128+i*48))
    offset=128+n*48
    print('NEXT ARRAY',hex(offset))
    for i in range(0,256,32):
        print(hex(offset+i),struct.unpack_from('<8I',b,offset+i))
