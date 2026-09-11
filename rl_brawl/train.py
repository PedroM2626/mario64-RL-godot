"""Backwards-compatible wrapper: actual logic lives in rl_common/train_sb3.py."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from rl_common.train_sb3 import main

if __name__ == "__main__":
    main()
