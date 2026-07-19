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
    default input #100ps output #100ps; 
    output req;
    output data;
    input  ack;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #100ps;
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

  property p_power_isolation_check;
    @(posedge clk) disable iff (!reset_n)
    (!pwr_stable && !iso_en) |-> $isunknown({req, ack, data});
  endproperty

  property p_power_active_no_x;
    @(posedge clk) disable iff (!reset_n)
    (pwr_stable && !iso_en) |-> !$isunknown({req, ack, data});
  endproperty

  property p_no_power_down_during_handshake;
    @(mon_cb) disable iff (!reset_n)
    (mon_cb.req && !mon_cb.ack) |-> pwr_stable;
  endproperty

  property p_no_activity_during_power_gate;
    @(mon_cb) disable iff (!reset_n)
    (!pwr_stable || iso_en) |-> !mon_cb.req;
  endproperty

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


endinterface
