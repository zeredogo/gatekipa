import os
import re

def main():
    lib_dir = '/Users/mac/Gatekeeper/lib'
    for root, dirs, files in os.walk(lib_dir):
        for file in files:
            if file.endsWith('.dart'):
                pass  # Just a quick check to see if python is available
