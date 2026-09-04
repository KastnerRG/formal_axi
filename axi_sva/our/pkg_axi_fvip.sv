package pkg_axi_fvip;

  //___________ ENUMS (AXI4) ___________ 

  // Table A3-3: Burst type encoding
  typedef enum logic [1:0] {
    BURST_FIXED = 2'b00,
    BURST_INCR  = 2'b01,
    BURST_WRAP  = 2'b10
    // 2'b11 reserved
  } burst_e;

  // Table A3-4: Response encoding
  typedef enum logic [1:0] {
    RESP_OKAY   = 2'b00,
    RESP_EXOKAY = 2'b01,
    RESP_SLVERR = 2'b10,
    RESP_DECERR = 2'b11
  } resp_e;

  // AXI4 uses 1-bit AxLOCK (A7.4)
  typedef enum logic {
    LOCK_NORMAL    = 1'b0,
    LOCK_EXCLUSIVE = 1'b1
  } lock_e;

  // Table A4-5: Memory type encoding (unique values only)
  // Note: different allocate hints share the same encoding;
  // only one name per unique 4-bit value is listed here.
  typedef enum logic [3:0] {
    CACHE_DEV_NON_BUF     = 4'b0000,  // Device Non-bufferable
    CACHE_DEV_BUF         = 4'b0001,  // Device Bufferable
    CACHE_NORM_NON_CACHE  = 4'b0010,  // Normal Non-cacheable Non-bufferable
    CACHE_NORM_BUF        = 4'b0011,  // Normal Non-cacheable Bufferable
    CACHE_WT_NO_ALLOC     = 4'b0110,  // Write-through No-allocate (also Read-allocate)
    CACHE_WB_NO_ALLOC     = 4'b0111,  // Write-back No-allocate (also Read-allocate)
    CACHE_WT_WR_ALLOC     = 4'b1010,  // Write-through Write-allocate (also No-allocate on AR)
    CACHE_WB_WR_ALLOC     = 4'b1011,  // Write-back Write-allocate (also No-allocate on AR)
    CACHE_WT_RW_ALLOC     = 4'b1110,  // Write-through Read-and-Write-allocate
    CACHE_WB_RW_ALLOC     = 4'b1111   // Write-back Read-and-Write-allocate
  } cache_e;

  //___________ FUNCTIONS ___________

  let aligned_addr(addr, size) = (addr >> size) << size;
  let total_bytes(len, size)   = (len + 1) << size;
  let end_byte(addr, len, size) = aligned_addr(addr, size) + total_bytes(len, size) - 1;

  function automatic logic [127:0] wstrb_legal_lanes(
    // wstrb_legal_lanes — legal byte-lane mask for one W beat
    //
    // Follows A3.4.1 equations (not A3.4.2 pseudocode, which has an
    // inconsistency in the unaligned INCR addr-update — breaks
    // Figure A3-13 case 4).
    //
    // PULP axi_pkg bug: beat_upper_byte uses the aligned formula on
    // beats > 0 unconditionally, but A3.4.2 never sets aligned = TRUE
    // for FIXED.  Unaligned FIXED upper_byte overflows the bus width.
    input longint unsigned  awaddr,
    input logic [2:0]       awsize,
    input logic [1:0]       awburst,
    input logic [7:0]       awlen,
    input logic [7:0]       beat_idx,
    input int               DATA_W
    );

    longint unsigned num_bytes      = longint'(1) << awsize;
    longint unsigned bus_bytes      = DATA_W / 8;
    longint unsigned start_aligned  = aligned_addr(awaddr, awsize);  // package let

    // A3.4.1 Address_N + A3.4.2 aligned flag
    logic is_aligned;
    longint unsigned beat_addr, txn_bytes, wrap_boundary;
    int lower_lane, upper_lane;
    logic [127:0] legal_lanes;

    if (beat_idx == 0 || awburst == BURST_FIXED) begin
      // A3.4.2: FIXED never updates addr or is_aligned
      beat_addr  = awaddr;
      is_aligned = (awaddr == start_aligned);

    end else if (awburst == BURST_INCR) begin
      // A3.4.1: Address_N = Aligned_Address + (N-1) * Number_Bytes
      beat_addr  = start_aligned + longint'(beat_idx) * num_bytes;
      is_aligned = 1;

    end else begin
      // A3.4.1: WRAP — same as INCR with wrap-around
      txn_bytes      = total_bytes(awlen, awsize);  // package let
      wrap_boundary  = (awaddr / txn_bytes) * txn_bytes;

      beat_addr = start_aligned + longint'(beat_idx) * num_bytes;
      if (beat_addr >= wrap_boundary + txn_bytes)
        beat_addr -= txn_bytes;
      is_aligned = 1;
    end

    // A3.4.1 byte-lane equations (page A3-47)
    lower_lane = int'(beat_addr % bus_bytes);

    if (is_aligned)
      upper_lane = lower_lane + int'(num_bytes) - 1;
    else
      upper_lane = int'(  start_aligned + num_bytes - 1
                        - (beat_addr / bus_bytes) * bus_bytes);

    // A3.4.3: strobes HIGH only for valid byte lanes
    
    legal_lanes = '0;
    for (int i = lower_lane; i <= upper_lane; i++)
      legal_lanes[i] = 1'b1;
    return legal_lanes;

  endfunction

  function automatic logic wstrb_valid(
    // wstrb_valid — validate the full WSTRB vector for one W beat
    input longint unsigned  awaddr,
    input logic [2:0]       awsize,
    input logic [1:0]       awburst,
    input logic [7:0]       awlen,
    input logic [7:0]       beat_idx,
    input logic [127:0]     wstrb,
    input int               DATA_W
    );

    logic [127:0] legal_lanes;

    legal_lanes = wstrb_legal_lanes(
      awaddr, awsize, awburst, awlen, beat_idx, DATA_W);
    return (wstrb & ~legal_lanes) == '0;

  endfunction

  function automatic logic wstrb_lane_valid(
    // wstrb_lane_valid — validate one arbitrary WSTRB byte lane
    input longint unsigned  awaddr,
    input logic [2:0]       awsize,
    input logic [1:0]       awburst,
    input logic [7:0]       awlen,
    input logic [7:0]       beat_idx,
    input int unsigned      lane_idx,
    input logic             wstrb_lane,
    input int               DATA_W
    );

    logic [127:0] legal_lanes;

    legal_lanes = wstrb_legal_lanes(
      awaddr, awsize, awburst, awlen, beat_idx, DATA_W);
    if (!wstrb_lane)
      return 1'b1;
    if (lane_idx >= DATA_W / 8 || lane_idx >= 128)
      return 1'b0;
    return legal_lanes[lane_idx];

  endfunction


endpackage
