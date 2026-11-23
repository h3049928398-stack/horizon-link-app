"""Rebuild the OFL-licensed position-gain font using the shared offline pipeline."""
from prepare_flutter_fonts import main

if __name__ == '__main__':
    main(['--only', 'gain'])
