import sys
from pathlib import Path

# Make domain/application/infrastructure/interfaces importable without
# the project being an installed package.
sys.path.insert(0, str(Path(__file__).parent))
