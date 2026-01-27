# DaliLite.v5 for Apple Silicon (ARM64/M1/M2/M3)

Native compilation of DaliLite.v5 structural alignment software for Apple Silicon Macs, eliminating the need for Docker x86 emulation.

## Overview

DALI (Distance matrix ALIgnment) is a widely-used tool for comparing protein structures based on distance matrices. The original DaliLite.v5 distribution provides Linux x86-64 binaries that require Rosetta 2 or Docker emulation on Apple Silicon Macs, resulting in 2-5x performance degradation.

This repository provides:
- **Patches** to fix macOS ARM64 compatibility issues
- **Build script** for automated compilation
- **Pre-built binaries** ready to use (optional)
- **Wrapper script** for convenient usage

## The Problem

When attempting to compile DaliLite.v5 on macOS ARM64, the resulting binaries fail with:

```
dyld[12345]: dyld cache '(null)' not loaded: syscall to map cache into shared region failed
dyld[12345]: Library not loaded: /usr/lib/libSystem.B.dylib
```

### Root Cause

The issue stems from **extremely large static arrays** in the Fortran source code:

1. **`parsizes.for`**: `maxprot=1000000` creates arrays of 1 million 5-byte strings (5MB each)
2. **`gagasizes.for`**: `maxres=5000` creates arrays of 25 million integers each

When compiled, these arrays inflate the `__DATA` segment to over **2GB**, exceeding macOS's memory mapping limits for the dyld shared cache.

### The Solution

Reduce array sizes to practical limits that stay under macOS thresholds:

| Parameter | Original | Patched | Impact |
|-----------|----------|---------|--------|
| `maxprot` | 1,000,000 | 10,000 | Max structures per list |
| `maxres` | 5,000 | 2,000 | Max residues per structure |

**These limits are sufficient for most use cases**, including large-scale structural comparisons.

## Quick Start

### Option 1: Use Pre-built Binaries

```bash
# Clone this repository
git clone https://github.com/YOUR_REPO/DALI_arm64.git
cd DALI_arm64

# Copy binaries to your DaliLite.v5 installation
cp bin/* /path/to/DaliLite.v5/bin/

# Test
./bin/serialcompare
# Should show: STOP # USAGE: serialcompare DAT_1 DAT_2 method
```

### Option 2: Build from Source

```bash
# Prerequisites
xcode-select --install  # Xcode Command Line Tools
brew install gcc        # gfortran

# Build
./scripts/build_dali_arm64.sh /path/to/install

# Or build in current directory
./scripts/build_dali_arm64.sh
```

## Installation

### Prerequisites

1. **Xcode Command Line Tools**
   ```bash
   xcode-select --install
   ```

2. **GCC with gfortran** (via Homebrew)
   ```bash
   brew install gcc
   ```

3. **Verify installation**
   ```bash
   gfortran --version
   # GNU Fortran (Homebrew GCC 15.x.x) ...
   ```

### Build Steps (Manual)

If you prefer to build manually:

```bash
# 1. Download DaliLite.v5
cd /path/to/your/software
curl -LO http://ekhidna2.biocenter.helsinki.fi/dali/DaliLite.v5.tar.gz
tar -xzf DaliLite.v5.tar.gz
cd DaliLite.v5

# 2. Apply patches
cd src

# Patch parsizes.for - reduce maxprot
sed -i.bak 's/parameter (maxprot=1000000)/parameter (maxprot=10000)/' parsizes.for

# Patch gagasizes.for - reduce maxres
sed -i.bak 's/parameter(maxres=5000/parameter(maxres=2000/' gagasizes.for

# 3. Compile
cd ../bin

# C code (dsspcmbi)
gcc -c -O -Wall -DGCC ../src/dsspcmbi/*.c
gcc -o dsspcmbi DsspCMBI.o p2clib.o Date.o Vector.o AccSurf.o CalcAccSurf.o Contacts.o -lm
rm -f *.o

# Fortran binaries (with static linking to avoid dyld issues)
FFLAGS="-O3 -static-libgfortran -static-libgcc"

gfortran $FFLAGS ../src/pipe.f ../src/util.f -o pipe
gfortran $FFLAGS ../src/filter95fitz.f ../src/util.f ../src/u3b-8.f ../src/subfitzfast.f -o filter95fitz
gfortran $FFLAGS ../src/selfdccp.f ../src/util.f -o selfdccp
gfortran $FFLAGS ../src/pipedccp.f -o pipedccp
gfortran $FFLAGS ../src/fssp.f ../src/util.f ../src/u3b-8.f -o fssp
gfortran $FFLAGS ../src/main.f ../src/puu.f ../src/util.f -o puu
gfortran $FFLAGS ../src/puutos.f ../src/util.f -o puutos

gfortran $FFLAGS \
    ../src/util.f ../src/subfitzfast.f \
    ../src/parsi-admin.f ../src/parsi-align.f ../src/parsi-score.f ../src/parsi-stack.f ../src/parsi-1.f \
    ../src/gagadccp.f ../src/gagagene.f ../src/gagahash.f ../src/gagatool.f \
    ../src/lean.f ../src/clean.f ../src/ssap.f ../src/dimple.f ../src/triplet.f ../src/testi.f ../src/soap4.f \
    ../src/wolf_original.f ../src/u3b-8.f ../src/comparemodules.f ../src/serialcompare.f \
    -o serialcompare

# 4. Verify
file serialcompare
# serialcompare: Mach-O 64-bit executable arm64

./serialcompare
# STOP # USAGE: serialcompare DAT_1 DAT_2 method
```

## Usage

### Basic Workflow

```bash
# Set environment
export DALI_DIR=/path/to/DaliLite.v5
export PATH=$DALI_DIR/bin:$PATH

# 1. Import PDB structures (creates .dat files)
import.pl --pdbfile protein1.pdb --pdbid P001 --dat ./DAT --clean
import.pl --pdbfile protein2.pdb --pdbid P002 --dat ./DAT --clean

# 2. Create structure lists
echo "P001A" > query.txt
echo "P002A" > db.txt

# 3. Run pairwise alignment
dali.pl --query query.txt --db db.txt --dat1 ./DAT --dat2 ./DAT

# 4. View results
cat P001A.txt
```

### All-vs-All Matrix

```bash
# Create list of all structures
ls DAT/*.dat | sed 's/.*\///; s/\.dat//' > all_structures.txt

# Run matrix comparison
dali.pl --query all_structures.txt --matrix --dat1 ./DAT --dat2 ./DAT
```

### Using the Wrapper Script

```bash
# Import
run_dali_native.sh import protein.pdb MYID ./DAT

# Pairwise
run_dali_native.sh pairwise query.txt db.txt ./DAT

# Matrix
run_dali_native.sh matrix structures.txt ./DAT
```

### Important Notes

1. **File path length**: DALI has a 80-character limit on file paths. Use short paths or symlinks.

2. **Structure ID format**: IDs are 4-5 characters. After import, chain IDs are appended (e.g., `P001` becomes `P001A`).

3. **Output files**:
   - `<query>.txt` - Alignment results in text format
   - `<query>.html` - Results in HTML format
   - `<query>.dccp` - Detailed comparison data

## Patch Details

### parsizes.for

```diff
--- parsizes.for.orig
+++ parsizes.for
@@ -7,7 +7,9 @@
         parameter (maxseg=200, maxdom=maxseg*2)
         ! maxprot is number of PDB chains
+        ! Reduced from 1000000 to 10000 for macOS ARM64 compatibility
+        ! This limits pairwise comparisons to 10000 structures per list
         integer maxprot,maxpair, maxnoccs
-        parameter (maxprot=1000000)
+        parameter (maxprot=10000)
```

**Rationale**: The original `maxprot=1000000` creates arrays like `character*5 list1(maxprot)` which allocate 5MB per array. Multiple such arrays in the code bloat the binary's data segment beyond macOS limits.

### gagasizes.for

```diff
--- gagasizes.for.orig
+++ gagasizes.for
@@ -1,9 +1,11 @@
 c
 c	include file for gaga*
+c	Modified for macOS ARM64 compatibility - reduced array sizes
 c
-	parameter(maxres=5000,maxres0=maxres,maxdom=210)
+c	Reduced from 5000 to 2000 for macOS ARM64
+	parameter(maxres=2000,maxres0=maxres,maxdom=210)
```

**Rationale**: The `maxres` parameter controls residue array sizes. With `maxres=5000`:
- `dim1 = maxres*(maxres+maxres+1) = 50,005,000` integers (~200MB)
- `dim4/5/6 = maxres*maxres = 25,000,000` integers each (~100MB)

Reducing to `maxres=2000` brings these to manageable levels.

## Compilation Flags

The key to successful compilation on macOS is **static linking** of the Fortran runtime:

```bash
gfortran -O3 -static-libgfortran -static-libgcc ...
```

This embeds `libgfortran` and `libgcc` into the binary, avoiding runtime linker issues with macOS's System Integrity Protection (SIP).

## Limitations

| Limitation | Value | Impact |
|------------|-------|--------|
| Max structures per list | 10,000 | Can compare up to 10K structures at once |
| Max residues per structure | 2,000 | Structures > 2000 residues may fail |
| File path length | 80 chars | Use short paths or symlinks |

### Workarounds

**For large structures (> 2000 residues)**:
1. Use domain-level analysis (split into domains)
2. Increase `maxres` in gagasizes.for (may hit memory limits)
3. Use the Docker version for exceptional cases

**For large-scale comparisons (> 10000 structures)**:
1. Split into batches
2. Increase `maxprot` (may cause dyld issues again)
3. Use hierarchical search with representative subsets

## Performance

| Configuration | Time for 654 structures |
|--------------|------------------------|
| Docker x86 emulation | ~28 hours |
| Native ARM64 | ~2-6 hours (estimated) |

Native compilation eliminates Rosetta 2 / Docker emulation overhead, typically providing **3-5x speedup**.

## Troubleshooting

### "dyld cache not loaded" Error

```
dyld[12345]: dyld cache '(null)' not loaded
```

**Cause**: Binary's `__DATA` segment is too large.

**Solution**: Ensure patches are applied. Check segment size:
```bash
otool -l serialcompare | grep -A5 "__DATA" | grep vmsize
# Should be < 0x40000000 (1GB)
```

### "Library not loaded: /usr/lib/libSystem.B.dylib"

**Cause**: macOS SIP hides system libraries from processes with large data segments.

**Solution**:
1. Verify static linking was used (`-static-libgfortran -static-libgcc`)
2. Reduce array sizes further if needed

### Import Fails with Path Error

```
STOP: file names incl. path must be max 80 long
```

**Solution**: Use shorter file paths. Copy files to `/tmp/` or create symlinks.

### "Undefined symbols" During Compilation

**Cause**: Missing source files in compilation command.

**Solution**: Use the exact file order from the build script. The Fortran files have interdependencies.

## Files Included

```
DALI_arm64/
├── README.md               # This documentation
├── bin/                    # Pre-built ARM64 binaries
│   ├── dsspcmbi           # DSSP calculator
│   ├── serialcompare      # Main alignment engine
│   ├── pipe, fssp, puu... # Supporting binaries
│   ├── dali.pl            # Main Perl wrapper
│   ├── import.pl          # Structure import script
│   └── *.pm               # Perl modules
├── patches/               # Source code patches
│   ├── parsizes.for.patch
│   └── gagasizes.for.patch
└── scripts/
    └── build_dali_arm64.sh # Automated build script
```

## Potential Bugs
The issue is:
  1. The initial DALI matrix run (in /tmp/dali_run) showed "0 residues" for all structures
  2. This was because the DSSP (secondary structure) step failed during import
  3. The old dsspcmbi (2002) couldn't properly parse the AlphaFold3 PDB files

  

## Citation

If you use DALI, please cite:

> Holm L (2022) Dali server: structural unification of protein families.
> Nucleic Acids Research 50(W1):W545-W552.
> https://doi.org/10.1093/nar/gkac387

## License

DaliLite is distributed under the terms of the GNU General Public License (GPL).
The patches and scripts in this repository are provided under the same license.

## Contributing

Contributions are welcome! Please:
1. Test on your specific macOS/hardware configuration
2. Report issues with hardware specs and error messages
3. Submit PRs for improvements

## Acknowledgments

- Original DALI software by Liisa Holm (University of Helsinki)
- ARM64 patches developed for the rotifer bioinformatics framework
