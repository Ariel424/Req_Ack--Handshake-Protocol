interface my_interface #(parameter int DATA_WIDTH = 8) (input logic clk); 

  logic reset_n; 
  logic req; 
  logic ack; 
  logic [DATA_WIDTH-1:0] data;
  
  // --- Power-Aware Simulation Signals (UPF Connected) ---
  logic pwr_stable; // 0: Block is Power-Gated (Off), 1: Block is Powered (On)
  logic iso_en;     // 0: Isolation Disabled, 1: Isolation Enabled (Clamping Active)
  bit assertions_en = 1; 

  // --- Clocking Blocks ---
  clocking drv_cb @(posedge clk);
    default input #1ns output #1ns; 
    output req;
    output data;
    input  ack;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #1ns;
    input req;
    input data;
    input ack;
  endclocking

  // --- Modports ---
  modport DRIVER_MP  (clocking drv_cb, input reset_n);
  modport MONITOR_MP (clocking mon_cb, input reset_n);

  // =========================================================================
  // ARIEL TOPAZ - STANDARD PROTOCOL CHECKERS (SVA)
  // =========================================================================
    
  // DATA STABILITY: Data must remain stable from REQ until ACK is asserted
  property p_data_stability;
    @(mon_cb) disable iff (!reset_n || !assertions_en)
    (mon_cb.req && !mon_cb.ack) |=> $stable(data) throughout (ack [->1]);
  endproperty 

  // NO SPURIOUS ACK: ACK cannot rise without an active REQ
  property p_no_spurious_ack;
    @(mon_cb) disable iff (!reset_n || !assertions_en)
    $rose(mon_cb.ack) -> req;
  endproperty

  // REQ PERSISTENCE: REQ must remain high until ACK is received
  property p_req_persistence; 
    @(mon_cb) disable iff (!reset_n || !assertions_en)
    (mon_cb.req && !mon_cb.ack) |=> req until_with ack;
  endproperty

  // --- Standard Assertion Directives ---
  assert_data_stability: assert property (p_data_stability) 
    else $error("[SVA ERROR] DATA toggled while waiting for ACK");
               
  assert_act_valid: assert property (p_no_spurious_ack)
    else $error("[SVA ERROR] ACK rose without a valid REQ!");

  assert_req_persistence: assert property (p_req_persistence)
    else $error("[SVA ERROR] REQ dropped before ACK was received!");


  // =========================================================================
  // ARIEL TOPAZ - POWER-AWARE ADVANCED PROTOCOL CHECKERS (SVA)
  // Designed for catching critical power domain transition bugs (Qualcomm/NeoLogic style)
  // =========================================================================

  // 1. ISOLATION CHECK (X-Propagation Prevention): 
  // Enforces that when the block is powered down, isolation MUST be enabled.
  // This prevents floating un-driven signals ('X') from leaking into the active SoC.
  property p_power_isolation_check;
    @(posedge clk) disable iff (!reset_n)
    (!pwr_stable && !iso_en) |-> $isunknown({req, ack, data});
  endproperty

  // 2. ACTIVE STATE CLEANLINESS:
  // Ensures no X-State propagation occurs on protocol lines during normal operation.
  property p_power_active_no_x;
    @(posedge clk) disable iff (!reset_n)
    (pwr_stable && !iso_en) |-> !$isunknown({req, ack, data});
  endproperty

  // 3. ILLEGAL POWER GATING (Mid-Transaction Shutdown):
  // Critical Check: Prevent Power Controller from shutting down the block while a 
  // handshake is pending (REQ is high but ACK hasn't responded). Avoids system Deadlocks.
  property p_no_power_down_during_handshake;
    @(mon_cb) disable iff (!reset_n)
    (mon_cb.req && !mon_cb.ack) |-> pwr_stable;
  endproperty

  // 4. POWER-GATED ACTIVITY VIOLATION:
  // Prevents any peripheral bus (like APB) or master from driving a REQ while 
  // the block is shut down or isolated.
  property p_no_activity_during_power_gate;
    @(mon_cb) disable iff (!reset_n)
    (!pwr_stable || iso_en) |-> !mon_cb.req;
  endproperty

  // 5. WAKE-UP LATENCY WATCHDOG:
  // Verifies that once power is stable, the daisy-chain or power controller 
  // successfully de-asserts isolation within a strict budget of 16 clock cycles.
  property p_wakeup_latency_limit;
    @(posedge clk) disable iff (!reset_n)
    $rose(pwr_stable) |-> ##[1:16] (!iso_en);
  endproperty


  // --- Power-Aware Assertion Directives ---
  
  assert_pwr_isolation: assert property (p_power_isolation_check)
    else $error("[ARIEL POWER ERROR] Isolation Enable (iso_en) is missing while block power is down! X-State leakage hazard.");

  assert_pwr_active_clean: assert property (p_power_active_no_x)
    else $error("[ARIEL POWER ERROR] X-State detected on operational protocol lines while power is stable.");

  assert_safe_power_down: assert property (p_no_power_down_during_handshake)
    else $error("[ARIEL POWER ERROR] Critical Bug! Block power went down mid-transaction (REQ high, ACK pending). System Deadlock.");

  assert_no_req_while_power_gated: assert property (p_no_activity_during_power_gate)
    else $error("[ARIEL POWER ERROR] Protocol Violation! REQ asserted while the block is Power-Gated/Isolated.");

  assert_wakeup_timeout: assert property (p_wakeup_latency_limit)
    else $error("[ARIEL POWER ERROR] Wake-up Timeout! Block failed to de-assert Isolation within 16 clock cycles from power-up.");


  // =========================================================================
  // ARIEL TOPAZ - COVERAGE MATRIX
  // =========================================================================

  // Functional Coverage (Timing & Protocol)
  covergroup cg_handshake_timing @(mon_cb);
    option.per_instance = 1;
    option.name = "Protocol_Timing_Coverage";

    cp_ack_latency: coverpoint ($countones(req && !ack)) {
        bins immediate = {0};      
        bins fast      = {1};      
        bins medium    = {[2:5]};   
        bins slow      = {[6:20]};  
        bins timeout   = {21};     
    }

    cp_idle_between_req: coverpoint ($countones(!req && !ack)) {
        bins back_to_back = {0};    
        bins short_idle   = {1};
        bins long_idle    = {[2:50]};
    }
  endgroup

  // Power-Aware Functional Coverage
  covergroup cg_power_aware_protocol @(posedge clk);
    option.per_instance = 1;
    option.name = "Ariel_Power_Aware_Coverage";

    // Track that the environment successfully tested all legitimate power states
    cp_power_state: coverpoint {pwr_stable, iso_en} {
      bins block_active    = {2'b10};
      bins block_isolated  = {2'b11};
      bins block_shut_down = {2'b01};
      illegal_bins illegal_state = {2'b00}; // Powered down but not isolated is strictly forbidden
    }

    // Cross-coverage: Verify a REQ was initiated immediately after a fast wake-up sequence
    cross_wakeup_and_req: cross cp_power_state, cg_inst.cp_ack_latency {
      bins req_immediately_after_wakeup = binsof(cp_power_state) intersect {2'b10} && binsof(cg_inst.cp_ack_latency).immediate;
    }
  endgroup

  // --- Coverage Instances & Properties ---
  cg_handshake_timing cg_inst = new();  
  cg_power_aware_protocol cg_pwr_inst = new();

  cover_data_stability: cover property (p_data_stability);
  cover_req_ack_handshake: cover property (req ##[1:5] ack); 

endinterface
