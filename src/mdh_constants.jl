"""
MDH (Measurement Data Header) layout constants for Siemens twix files.

Byte offsets, bit positions, and struct sizes for VB and VD formats.
"""

# ─── Struct sizes ───────────────────────────────────────────────────────

const MDH_SIZE_VB = 128
const MDH_SIZE_VD = 184
const VD_SCAN_HEADER_SIZE = 192
const VD_CHANNEL_HEADER_SIZE = 32
const VB_CHANNEL_HEADER_SIZE = 128
const VD_EXTRA_BYTES = 20  # extra bytes in VD MDH removed during evalMDH

# ─── Binary layout offsets (1-based byte indices into MDH blob) ─────────

# After VD extra bytes are removed, both versions share this layout:
const UINT32_RANGE = 1:76            # 19 UInt32 fields
const UINT16_OFFSET = 29             # UInt16 fields start here
const FLOAT32_OFFSET = 69            # Float32 fields start here

# evalInfoMask byte offset in raw MDH blob (1-based)
const EVAL_INFO_OFFSET_VB = 21
const EVAL_INFO_OFFSET_VD = 41       # 21 + VD_EXTRA_BYTES

# DMA length / NCol+NCha location in raw MDH blob (1-based)
const DMA_IDX_VB = 29:32
const DMA_IDX_VD = 49:52             # 29:32 .+ VD_EXTRA_BYTES

# ─── UInt32 column indices (after reinterpret, 1-based) ─────────────────

const U32_DMA_LENGTH = 1             # ulDMALength (masked)
const U32_MEAS_UID = 2               # lMeasUID
const U32_SCAN_COUNTER = 3           # ulScanCounter
const U32_TIMESTAMP = 4              # ulTimeStamp
const U32_PMU_TIMESTAMP = 5          # ulPMUTimeStamp
const U32_EVAL_INFO_MASK = 6:7       # aulEvalInfoMask[2]
const U32_TIME_SINCE_RF = 19         # ulTimeSinceLastRF

# ─── UInt16 column indices (after reinterpret from UINT16_OFFSET) ──────

const U16_SAMPLES_IN_SCAN = 1        # ushSamplesInScan
const U16_USED_CHANNELS = 2          # ushUsedChannels
const U16_SLC = 3:16                 # sLC[14] — loop counters
const U16_CUT_OFF = 17:18            # sCutOff[2]
const U16_KSPACE_CENTRE_COL = 19     # ushKSpaceCentreColumn
const U16_COIL_SELECT = 20           # ushCoilSelect
const U16_KSPACE_CENTRE_LINE = 25    # ushKSpaceCentreLineNo
const U16_KSPACE_CENTRE_PART = 26    # ushKSpaceCentrePartitionNo

# ─── Float32 column indices (after reinterpret from FLOAT32_OFFSET) ────

const F32_READOUT_OFFCENTRE = 1      # fReadOutOffcentre
# Slice position and ice params differ between VB/VD:
const F32_SLICE_POS_VD = 4:10
const F32_SLICE_POS_VB = 8:14
const U16_ICE_PARAM_VD = 41:64
const U16_ICE_PARAM_VB = 27:30
const U16_FREE_PARAM_VD = 65:68
const U16_FREE_PARAM_VB = 31:34

# ─── EvalInfoMask bit positions (0-indexed) ─────────────────────────────

const BIT_ACQEND = 0
const BIT_RTFEEDBACK = 1
const BIT_HPFEEDBACK = 2
const BIT_SYNCDATA = 5
const BIT_RAWDATACORRECTION = 10
const BIT_REFPHASESTABSCAN = 14
const BIT_PHASESTABSCAN = 15
const BIT_SIGNREV = 17
const BIT_PHASCOR = 21
const BIT_PATREFSCAN = 22
const BIT_PATREFANDIMASCAN = 23
const BIT_REFLECT = 24
const BIT_NOISEADJSCAN = 25
const BIT_VOP = 53                   # in second UInt32 word (bit 53-32=21)

# Byte-level masks used in loop_mdh_read
const BYTE_BIT_0 = UInt8(1)          # ACQEND
const BYTE_BIT_5 = UInt8(32)         # SYNCDATA

# ─── Dimension names (in canonical order) ───────────────────────────────

const DIM_NAMES = ["Col", "Cha", "Lin", "Par", "Sli", "Ave", "Phs",
                   "Eco", "Rep", "Set", "Seg", "Ida", "Idb", "Idc", "Idd", "Ide"]
const N_DIMS = 16

# Dimension index helpers (1-based)
const DIM_COL = 1
const DIM_CHA = 2
const DIM_LIN = 3
const DIM_PAR = 4
const DIM_SLI = 5
const DIM_AVE = 6
const DIM_PHS = 7
const DIM_ECO = 8
const DIM_REP = 9
const DIM_SET = 10
const DIM_SEG = 11
const DIM_IDA = 12
const DIM_IDB = 13
const DIM_IDC = 14
const DIM_IDD = 15
const DIM_IDE = 16

# ─── Scan type names ───────────────────────────────────────────────────

const SCAN_TYPES = [
    "image", "noise", "phasecor", "phasestab",
    "phasestab_ref0", "phasestab_ref1",
    "refscan", "refscanPC",
    "refscan_phasestab", "refscan_phasestab_ref0", "refscan_phasestab_ref1",
    "rtfeedback", "vop"
]