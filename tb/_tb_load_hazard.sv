`timescale 1ns/1ps

module tb_load_hazard;
    logic clk;
    logic reset;
    integer stall_count;
    integer stall_at_44;
    integer stall_at_56;
    integer stall_at_68;
    integer stall_at_128;
    integer stall_at_140;
    logic hold_pending;
    logic [31:0] held_pcf;
    logic [31:0] held_instrd;
    logic [31:0] held_pcd;
    logic seen_forward_a;
    logic seen_forward_b;
    logic seen_branch_forward;
    logic seen_false_lui;
    logic seen_false_auipc;
    logic seen_false_addi;
    logic seen_store_data_no_stall;
    logic seen_store_data_bypass;
    logic seen_store_address;
    logic seen_store_both;
    logic seen_x0_no_stall;
    logic seen_alu_store;

    riscv_system_top #(
        .IMEM_INIT_FILE ("../mem/load_hazard.hex")
    ) dut (
        .clk   (clk),
        .reset (reset)
    );

    function automatic logic [31:0] physical_word(input integer index);
        physical_word = {
            dut.u_data_memory.mem_byte3[index],
            dut.u_data_memory.mem_byte2[index],
            dut.u_data_memory.mem_byte1[index],
            dut.u_data_memory.mem_byte0[index]
        };
    endfunction

    always #5 clk = ~clk;

    // O teste observa o pipeline no meio do ciclo, quando a deteccao de hazard
    // e os muxes de forwarding ja estao estaveis para o proximo flanco.
    always @(negedge clk) begin
        if (!reset) begin
            // Um ciclo depois da deteccao, PC e IF/ID ainda devem guardar a
            // mesma instrucao, enquanto uma bolha ocupa Execute.
            if (hold_pending) begin
                if (dut.u_riscv_core.StallF || dut.u_riscv_core.StallD)
                    $fatal(1, "FAIL: load-use lasted more than one cycle at PC=%0d",
                           held_pcd);
                if ((dut.PCF !== held_pcf) || (dut.InstrD !== held_instrd) ||
                    (dut.PCD !== held_pcd))
                    $fatal(1, "FAIL: PC or IF/ID changed during load-use stall");
                if (dut.RegWriteE || dut.MemWriteE ||
                    (dut.ResultSrcE !== 2'b00))
                    $fatal(1, "FAIL: FlushE did not insert a safe bubble");
                if ((dut.u_riscv_core.u_datapath.ResultSrcM !== 2'b01) ||
                    (dut.u_riscv_core.RdM !== 5'd5))
                    $fatal(1, "FAIL: LOAD did not continue from E to M");
                hold_pending = 1'b0;
            end

            if (dut.u_riscv_core.StallF || dut.u_riscv_core.StallD) begin
                if (!dut.u_riscv_core.StallF || !dut.u_riscv_core.StallD ||
                    dut.u_riscv_core.FlushD || !dut.u_riscv_core.FlushE)
                    $fatal(1, "FAIL: incomplete load-use stall/flush controls");
                if ((dut.ResultSrcE !== 2'b01) || (dut.RdE !== 5'd5))
                    $fatal(1, "FAIL: stall was not caused by the expected LOAD");

                stall_count = stall_count + 1;
                case (dut.PCD)
                    32'd44:  stall_at_44  = stall_at_44 + 1;
                    32'd56:  stall_at_56  = stall_at_56 + 1;
                    32'd68:  stall_at_68  = stall_at_68 + 1;
                    32'd128: stall_at_128 = stall_at_128 + 1;
                    32'd140: stall_at_140 = stall_at_140 + 1;
                    default: $fatal(1, "FAIL: unexpected stall at Decode PC=%0d",
                                    dut.PCD);
                endcase

                held_pcf    = dut.PCF;
                held_instrd = dut.InstrD;
                held_pcd    = dut.PCD;
                hold_pending = 1'b1;
            end

            // Depois da bolha, o LOAD esta em W e o consumidor recebe ResultW.
            case (dut.PCE)
                32'd44: begin
                    if ((dut.u_riscv_core.ForwardAE !== 2'b01) ||
                        (dut.u_riscv_core.RdW !== 5'd5) ||
                        (dut.u_riscv_core.u_datapath.ResultW !== 32'd42) ||
                        (dut.ALUResultE !== 32'd43))
                        $fatal(1, "FAIL: rs1 consumer did not receive ResultW");
                    seen_forward_a = 1'b1;
                end
                32'd56: begin
                    if ((dut.u_riscv_core.ForwardBE !== 2'b01) ||
                        (dut.u_riscv_core.u_datapath.ResultW !== 32'd42) ||
                        (dut.ALUResultE !== 32'd47))
                        $fatal(1, "FAIL: rs2 consumer did not receive ResultW");
                    seen_forward_b = 1'b1;
                end
                32'd68: begin
                    if ((dut.u_riscv_core.ForwardAE !== 2'b01) ||
                        !dut.u_riscv_core.PCSrcE ||
                        !dut.u_riscv_core.FlushD || !dut.u_riscv_core.FlushE ||
                        dut.u_riscv_core.StallF || dut.u_riscv_core.StallD)
                        $fatal(1, "FAIL: LOAD to branch forwarding/redirect");
                    seen_branch_forward = 1'b1;
                end
                32'd128: begin
                    if ((dut.u_riscv_core.ForwardAE !== 2'b01) ||
                        (dut.ALUResultE !== 32'h0000_0124))
                        $fatal(1, "FAIL: LOAD to STORE address forwarding");
                    seen_store_address = 1'b1;
                end
                32'd140: begin
                    if ((dut.u_riscv_core.ForwardAE !== 2'b01) ||
                        (dut.u_riscv_core.ForwardBE !== 2'b01) ||
                        (dut.ALUResultE !== 32'h0000_0128) ||
                        (dut.WriteDataE !== 32'h0000_0128))
                        $fatal(1, "FAIL: LOAD to STORE rs1/rs2 forwarding");
                    seen_store_both = 1'b1;
                end
                default: begin
                end
            endcase

            // Estes pares colocam um LOAD em E e uma instrucao em D cujos bits
            // parecem rs1/rs2, mas o formato nao usa aquela fonte arquitetural.
            if ((dut.PCE == 32'd84) && (dut.PCD == 32'd88)) begin
                if (dut.u_riscv_core.UsesRs1D || dut.u_riscv_core.UsesRs2D ||
                    dut.u_riscv_core.StallF || dut.u_riscv_core.StallD)
                    $fatal(1, "FAIL: false load-use stall for LUI");
                seen_false_lui = 1'b1;
            end
            if ((dut.PCE == 32'd92) && (dut.PCD == 32'd96)) begin
                if (dut.u_riscv_core.UsesRs1D || dut.u_riscv_core.UsesRs2D ||
                    dut.u_riscv_core.StallF || dut.u_riscv_core.StallD)
                    $fatal(1, "FAIL: false load-use stall for AUIPC");
                seen_false_auipc = 1'b1;
            end
            if ((dut.PCE == 32'd100) && (dut.PCD == 32'd104)) begin
                if (!dut.u_riscv_core.UsesRs1D || dut.u_riscv_core.UsesRs2D ||
                    (dut.Rs2D !== 5'd5) || dut.u_riscv_core.StallF ||
                    dut.u_riscv_core.StallD)
                    $fatal(1, "FAIL: ADDI immediate bits caused a false stall");
                seen_false_addi = 1'b1;
            end

            // Dependencia exclusiva em STORE.rs2 nao para Decode. WriteDataE
            // pode ser transitorio; o valor arquitetural e corrigido em MEM.
            if ((dut.PCE == 32'd108) && (dut.PCD == 32'd112)) begin
                if (!dut.u_riscv_core.MemWriteD ||
                    (dut.Rs2D !== 5'd5) || dut.u_riscv_core.StallF ||
                    dut.u_riscv_core.StallD)
                    $fatal(1, "FAIL: LOAD to STORE data-only generated a stall");
                seen_store_data_no_stall = 1'b1;
            end

            if (dut.MemWriteM && (dut.ALUResultM == 32'h0000_0120)) begin
                if ((dut.Rs2M !== 5'd5) || !dut.u_riscv_core.RegWriteW ||
                    (dut.u_riscv_core.RdW !== 5'd5) ||
                    (dut.StoreWriteDataM !== dut.u_riscv_core.u_datapath.ResultW) ||
                    (dut.StoreWriteDataM !== 32'd42))
                    $fatal(1, "FAIL: late WB to MEM store-data forwarding");
                seen_store_data_bypass = 1'b1;
            end

            if ((dut.PCE == 32'd148) && (dut.PCD == 32'd152)) begin
                if ((dut.RdE !== 5'd0) || dut.u_riscv_core.StallF ||
                    dut.u_riscv_core.StallD)
                    $fatal(1, "FAIL: LOAD to x0 generated a stall");
                seen_x0_no_stall = 1'b1;
            end

            if (dut.MemWriteM && (dut.ALUResultM == 32'h0000_012c)) begin
                if (dut.StoreWriteDataM !== 32'd77)
                    $fatal(1, "FAIL: existing ALU to STORE forwarding changed");
                seen_alu_store = 1'b1;
            end
        end
    end

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        stall_count = 0;
        stall_at_44 = 0;
        stall_at_56 = 0;
        stall_at_68 = 0;
        stall_at_128 = 0;
        stall_at_140 = 0;
        hold_pending = 1'b0;
        seen_forward_a = 1'b0;
        seen_forward_b = 1'b0;
        seen_branch_forward = 1'b0;
        seen_false_lui = 1'b0;
        seen_false_auipc = 1'b0;
        seen_false_addi = 1'b0;
        seen_store_data_no_stall = 1'b0;
        seen_store_data_bypass = 1'b0;
        seen_store_address = 1'b0;
        seen_store_both = 1'b0;
        seen_x0_no_stall = 1'b0;
        seen_alu_store = 1'b0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
        repeat (75) @(posedge clk);
        @(negedge clk);

        if (hold_pending)
            $fatal(1, "FAIL: test ended with an unresolved stall");
        if ((stall_count != 5) || (stall_at_44 != 1) ||
            (stall_at_56 != 1) || (stall_at_68 != 1) ||
            (stall_at_128 != 1) || (stall_at_140 != 1))
            $fatal(1, "FAIL: expected exactly one cycle in each real load-use");
        if (!seen_forward_a || !seen_forward_b || !seen_branch_forward ||
            !seen_false_lui || !seen_false_auipc || !seen_false_addi ||
            !seen_store_data_no_stall || !seen_store_data_bypass ||
            !seen_store_address || !seen_store_both ||
            !seen_x0_no_stall || !seen_alu_store)
            $fatal(1, "FAIL: a required load hazard scenario was not observed");

        if ((dut.u_riscv_core.u_datapath.u_register_file.regs[10] !== 32'd43) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[11] !== 32'd47) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[12] !== 32'd12) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[13] !== 32'h0002_8000) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[14] !== 32'h0002_8060) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[15] !== 32'd5) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[16] !== 32'd1) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[18] !== 32'd42))
            $fatal(1, "FAIL: final Register File values are incorrect");

        if ((physical_word(32'h120 >> 2) !== 32'd42) ||
            (physical_word(32'h124 >> 2) !== 32'd5) ||
            (physical_word(32'h128 >> 2) !== 32'h0000_0128) ||
            (physical_word(32'h12c >> 2) !== 32'd77) ||
            (physical_word(32'h130 >> 2) !== 32'b0))
            $fatal(1, "FAIL: final STORE results are incorrect");

        $display("PASS: five real load-use dependencies stalled exactly once");
        $display("PASS: UsesRs prevented false LUI, AUIPC and ADDI stalls");
        $display("PASS: late WB-to-MEM STORE data bypass wrote the loaded value");
        $display("PASS: branch, STORE address, x0 and ALU-to-STORE cases passed");
        $finish;
    end
endmodule
