# Real X12 EDI Sample Files

This directory contains real-world X12 837 EDI sample files obtained from open-source repositories for testing purposes. All files are anonymized/sanitized and contain no actual PHI (Protected Health Information).

## Files

### 837P (Professional Claims)

1. **837P_databricks.txt** (1.1 KB)
   - Source: Databricks X12 EDI Parser
   - Contains: 2 professional claims with service lines
   - Features: LX segments, SV1 professional services, standard 5010X222A1

2. **837P_CC.txt** (1.0 KB)
   - Source: Databricks X12 EDI Parser
   - Compact 837P example
   - Version: 005010X222A1

3. **837P_Molina_Mock.txt** (3.7 KB)
   - Source: Databricks X12 EDI Parser
   - Mock data from Molina Healthcare format
   - Larger file with more complex structure

### 837I (Institutional Claims)

4. **837I_databricks_CHPW.txt** (5.2 KB)
   - Source: Databricks X12 EDI Parser
   - Contains: 5 institutional claims
   - Provider: BH CLINIC OF VANCOUVER
   - Features: SV2 segments (revenue codes), may lack LX segments
   - Version: 005010X222A1

5. **837I_CC.txt** (1.6 KB)
   - Source: Databricks X12 EDI Parser
   - Compact institutional claim example
   - Version: 005010X223A2

## Sources

All files sourced from:
- **Databricks X12 EDI Parser**: https://github.com/databricks-industry-solutions/x12-edi-parser
  - Open-source EDI parser project
  - Sample data in `sampledata/837/` directory
  - Licensed for educational and testing purposes

## Usage

These files are ideal for:
- Testing parser implementation against real-world variations
- Validating 837P vs 837I differences
- Testing edge cases (missing LX segments, different loop structures)
- Performance testing with various file sizes

## Important Notes

- **No PHI**: All files contain anonymized/mock data
- **Standards Compliance**: Files follow X12 5010 standard (005010X222A1 or 005010X223A2)
- **Real-World Variations**: Files exhibit actual variations found in production EDI files
- **Legal Use**: These are public domain sample files from open-source projects

## Testing Recommendations

1. Start with **837P_databricks.txt** - cleanest, simplest structure
2. Test with **837I_databricks_CHPW.txt** - tests missing LX segments
3. Try **837P_Molina_Mock.txt** - larger file, more complex
4. Compare outputs between 837P and 837I versions

## Last Updated

Downloaded: January 9, 2026
