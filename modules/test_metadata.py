#!/usr/bin/env python3
"""
Test script for parameter metadata loader.
Run this to verify that metadata is being downloaded and parsed correctly.

Usage:
    python test_metadata.py
"""

import sys
import time
from pathlib import Path

# Add the modules directory to path if needed
sys.path.insert(0, str(Path(__file__).parent))

from param_metadata_loader import ParamMetadataLoader


def main():
    print("=" * 70)
    print("PARAMETER METADATA LOADER TEST")
    print("=" * 70)
    print()

    # Create loader
    print("Creating ParamMetadataLoader for ArduCopter...")
    loader = ParamMetadataLoader(vehicle_type="ArduCopter")
    
    # Wait for it to load
    print("Waiting for metadata to load (timeout: 60s)...")
    start = time.time()
    success = loader.wait_until_loaded(timeout=60.0)
    elapsed = time.time() - start
    
    print()
    print("=" * 70)
    if success:
        print(f"✅ Metadata loaded successfully in {elapsed:.1f}s")
    else:
        print(f"❌ Metadata loading timed out after {elapsed:.1f}s")
    print("=" * 70)
    print()
    
    # Check what we got
    with loader._lock:
        metadata = dict(loader._metadata)
    
    total_params = len(metadata)
    desc_count = sum(1 for v in metadata.values() if v.get("description"))
    units_count = sum(1 for v in metadata.values() if v.get("units"))
    range_count = sum(1 for v in metadata.values() if v.get("range"))
    default_count = sum(1 for v in metadata.values() if v.get("default"))
    
    print(f"📊 STATISTICS:")
    print(f"   Total parameters:     {total_params}")
    print(f"   With descriptions:    {desc_count} ({desc_count*100//total_params if total_params else 0}%)")
    print(f"   With units:           {units_count} ({units_count*100//total_params if total_params else 0}%)")
    print(f"   With range:           {range_count} ({range_count*100//total_params if total_params else 0}%)")
    print(f"   With default:         {default_count} ({default_count*100//total_params if total_params else 0}%)")
    print()
    
    # Show some examples
    if total_params > 0:
        print("=" * 70)
        print("📋 SAMPLE PARAMETERS (first 5):")
        print("=" * 70)
        
        for i, (name, meta) in enumerate(list(metadata.items())[:5], 1):
            print(f"\n{i}. {name}")
            print(f"   Description: {meta.get('description', '(none)')[:70]}")
            if len(meta.get('description', '')) > 70:
                print(f"                {meta.get('description', '')[70:140]}")
            print(f"   Units:       {meta.get('units', '(none)')}")
            print(f"   Range:       {meta.get('range', '(none)')[:70]}")
            if len(meta.get('range', '')) > 70:
                print(f"                {meta.get('range', '')[70:140]}")
            print(f"   Default:     {meta.get('default', '(none)')}")
    else:
        print("❌ No parameters loaded!")
        print()
        print("TROUBLESHOOTING:")
        print("1. Check your internet connection")
        print("2. Try deleting the cache: ~/.tihanfly/param_metadata/")
        print("3. Check if https://autotest.ardupilot.org is accessible")
    
    print()
    print("=" * 70)
    
    # Test the enrichment function
    if total_params > 0:
        print("\n🧪 TESTING ENRICHMENT:")
        print("=" * 70)
        
        # Create some fake parameters
        test_params = {}
        sample_names = list(metadata.keys())[:3]
        
        for name in sample_names:
            test_params[name] = {
                "name": name,
                "value": "0.0",
                "type": "FLOAT",
                "description": "",
                "units": "",
                "range": "",
                "default": "",
                "desc": "",
                "options": ""
            }
        
        print(f"Created {len(test_params)} test parameters:")
        for name in test_params:
            print(f"  - {name}")
        
        print("\nEnriching parameters...")
        loader.enrich_parameters(test_params)
        
        print("\nAfter enrichment:")
        for name, data in test_params.items():
            print(f"\n  {name}:")
            print(f"    description: '{data.get('description', '')[:60]}'")
            print(f"    units:       '{data.get('units', '')}'")
            print(f"    range:       '{data.get('range', '')[:60]}'")
            print(f"    desc:        '{data.get('desc', '')[:60]}'")
            print(f"    options:     '{data.get('options', '')[:60]}'")
    
    print()
    print("=" * 70)
    print("TEST COMPLETE")
    print("=" * 70)


if __name__ == "__main__":
    main()
