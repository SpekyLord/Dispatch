import sys
import os

# Make the src directory importable
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from dispatch_api.app import create_app

app = create_app()
