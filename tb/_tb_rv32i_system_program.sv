`timescale 1ns/1ps

// Teste de sistema do RV32I: a IMEM recebe um programa bare-metal completo e
// toda inicializacao da DMEM acontece por instrucoes executadas pelo processador.
module tb_rv32i_system_program;
    `include "rv32i_system_program_symbols.svh"

    localparam integer TIMEOUT_CYCLES = 5000;
    localparam logic [31:0] STACK_LOW  = 32'h0000_0700;
    localparam logic [31:0] STACK_HIGH = 32'h0000_07ff;

    logic clk;
    logic reset;

    logic [36:0] isa_seen;
    integer cycle_count;
    integer load_use_stall_count;
    integer forward_m_a_count;
    integer forward_m_b_count;
    integer forward_w_a_count;
    integer forward_w_b_count;
    integer store_bypass_count;
    integer wb_decode_count;
    integer branch_taken_count;
    integer branch_not_taken_count;
    integer redirect_count;
    integer call_count;
    integer return_count;
    integer stack_write_count;
    integer stack_read_count;
    integer recursion_depth;
    integer max_recursion_depth;
    integer binary_call_count;
    logic [31:0] min_sp;
    logic [31:0] min_stack_address;
    logic        seen_load_store_no_stall;

    riscv_system_top #(
        .IMEM_INIT_FILE ("../mem/rv32i_system_program.hex")
    ) dut (
        .clk   (clk),
        .reset (reset)
    );

    // ------------------------------------------------------------
    // 1. Clock, reset e waveform
    // ------------------------------------------------------------
    always #5 clk = ~clk;

    initial begin
        $fsdbDumpfile("rv32i_system_program.fsdb");
        $fsdbDumpvars(0, tb_rv32i_system_program);
        $fsdbDumpMDA(0, tb_rv32i_system_program);
    end

    // ------------------------------------------------------------
    // 2. Leitura observacional da DMEM
    // ------------------------------------------------------------
    // O testbench nunca escreve nesses bancos. As funcoes abaixo apenas juntam
    // os quatro byte lanes do DUT para conferir o estado arquitetural final.
    function automatic logic [31:0] physical_word(input integer byte_address);
        integer index;
        begin
            index = byte_address >> 2;
            physical_word = {
                dut.u_data_memory.mem_byte3[index],
                dut.u_data_memory.mem_byte2[index],
                dut.u_data_memory.mem_byte1[index],
                dut.u_data_memory.mem_byte0[index]
            };
        end
    endfunction

    function automatic logic [7:0] physical_byte(input integer byte_address);
        integer index;
        begin
            index = byte_address >> 2;
            case (byte_address & 3)
                0: physical_byte = dut.u_data_memory.mem_byte0[index];
                1: physical_byte = dut.u_data_memory.mem_byte1[index];
                2: physical_byte = dut.u_data_memory.mem_byte2[index];
                default: physical_byte = dut.u_data_memory.mem_byte3[index];
            endcase
        end
    endfunction

    task automatic expect_word(
        input integer address,
        input logic [31:0] expected,
        input string description
    );
        logic [31:0] actual;
        begin
            actual = physical_word(address);
            if (actual !== expected)
                $fatal(1, "FAIL %s: DMEM[%h]=%h, expected=%h",
                       description, address, actual, expected);
        end
    endtask

    // ------------------------------------------------------------
    // 3. Cobertura dinamica das 37 instrucoes
    // ------------------------------------------------------------
    // A classificacao usa a instrucao apontada por PCE. Assim uma palavra que
    // apenas existe no HEX, mas nunca alcanca Execute, nao conta como coberta.
    function automatic integer instruction_id(input logic [31:0] instruction);
        logic [6:0] opcode;
        logic [2:0] funct3;
        begin
            opcode = instruction[6:0];
            funct3 = instruction[14:12];
            instruction_id = -1;
            case (opcode)
                7'b0010011: begin
                    case (funct3)
                        3'b000: instruction_id = 0;  // ADDI
                        3'b001: instruction_id = 1;  // SLLI
                        3'b010: instruction_id = 2;  // SLTI
                        3'b011: instruction_id = 3;  // SLTIU
                        3'b100: instruction_id = 4;  // XORI
                        3'b101: instruction_id = instruction[30] ? 6 : 5; // SRAI/SRLI
                        3'b110: instruction_id = 7;  // ORI
                        3'b111: instruction_id = 8;  // ANDI
                        default: instruction_id = -1;
                    endcase
                end
                7'b0110011: begin
                    case (funct3)
                        3'b000: instruction_id = instruction[30] ? 10 : 9; // SUB/ADD
                        3'b001: instruction_id = 11; // SLL
                        3'b010: instruction_id = 12; // SLT
                        3'b011: instruction_id = 13; // SLTU
                        3'b100: instruction_id = 14; // XOR
                        3'b101: instruction_id = instruction[30] ? 16 : 15; // SRA/SRL
                        3'b110: instruction_id = 17; // OR
                        3'b111: instruction_id = 18; // AND
                        default: instruction_id = -1;
                    endcase
                end
                7'b0000011: begin
                    case (funct3)
                        3'b000: instruction_id = 19; // LB
                        3'b001: instruction_id = 20; // LH
                        3'b010: instruction_id = 21; // LW
                        3'b100: instruction_id = 22; // LBU
                        3'b101: instruction_id = 23; // LHU
                        default: instruction_id = -1;
                    endcase
                end
                7'b0100011: begin
                    case (funct3)
                        3'b000: instruction_id = 24; // SB
                        3'b001: instruction_id = 25; // SH
                        3'b010: instruction_id = 26; // SW
                        default: instruction_id = -1;
                    endcase
                end
                7'b1100011: begin
                    case (funct3)
                        3'b000: instruction_id = 27; // BEQ
                        3'b001: instruction_id = 28; // BNE
                        3'b100: instruction_id = 29; // BLT
                        3'b101: instruction_id = 30; // BGE
                        3'b110: instruction_id = 31; // BLTU
                        3'b111: instruction_id = 32; // BGEU
                        default: instruction_id = -1;
                    endcase
                end
                7'b0110111: instruction_id = 33; // LUI
                7'b0010111: instruction_id = 34; // AUIPC
                7'b1101111: instruction_id = 35; // JAL
                7'b1100111: instruction_id = 36; // JALR
                default: instruction_id = -1;
            endcase
        end
    endfunction

    function automatic string instruction_name(input integer id);
        begin
            case (id)
                0: instruction_name="ADDI";  1: instruction_name="SLLI";
                2: instruction_name="SLTI";  3: instruction_name="SLTIU";
                4: instruction_name="XORI";  5: instruction_name="SRLI";
                6: instruction_name="SRAI";  7: instruction_name="ORI";
                8: instruction_name="ANDI";  9: instruction_name="ADD";
                10: instruction_name="SUB"; 11: instruction_name="SLL";
                12: instruction_name="SLT"; 13: instruction_name="SLTU";
                14: instruction_name="XOR"; 15: instruction_name="SRL";
                16: instruction_name="SRA"; 17: instruction_name="OR";
                18: instruction_name="AND"; 19: instruction_name="LB";
                20: instruction_name="LH"; 21: instruction_name="LW";
                22: instruction_name="LBU"; 23: instruction_name="LHU";
                24: instruction_name="SB"; 25: instruction_name="SH";
                26: instruction_name="SW"; 27: instruction_name="BEQ";
                28: instruction_name="BNE"; 29: instruction_name="BLT";
                30: instruction_name="BGE"; 31: instruction_name="BLTU";
                32: instruction_name="BGEU"; 33: instruction_name="LUI";
                34: instruction_name="AUIPC"; 35: instruction_name="JAL";
                36: instruction_name="JALR";
                default: instruction_name="UNKNOWN";
            endcase
        end
    endfunction

    // ------------------------------------------------------------
    // 4. Monitor de chamadas, stack, hazards e forwarding
    // ------------------------------------------------------------
    // O negedge fica no meio do ciclo: controles combinacionais e registradores
    // de pipeline ja estao estaveis, longe do flanco que atualiza o estado.
    always @(negedge clk) begin : pipeline_monitor
        integer id;
        logic [31:0] execute_instruction;
        logic execute_valid;

        if (!reset) begin
            cycle_count = cycle_count + 1;

            execute_valid = dut.RegWriteE || dut.MemWriteE ||
                            dut.BranchE || dut.JumpE;
            if (execute_valid && (dut.PCE < PROGRAM_BYTES)) begin
                execute_instruction = dut.u_instruction_memory.mem[dut.PCE[10:2]];
                id = instruction_id(execute_instruction);
                if (id >= 0)
                    isa_seen[id] = 1'b1;
                else
                    $fatal(1, "FAIL: invalid instruction reached Execute: PC=%h word=%h",
                           dut.PCE, execute_instruction);
            end

            if (dut.u_riscv_core.StallF && dut.u_riscv_core.StallD &&
                dut.u_riscv_core.FlushE) begin
                if (dut.u_riscv_core.FlushD)
                    $fatal(1, "FAIL: load-use stall unexpectedly asserted FlushD");
                load_use_stall_count = load_use_stall_count + 1;
            end

            if (execute_valid) begin
                if (dut.u_riscv_core.ForwardAE == 2'b10) forward_m_a_count++;
                if (dut.u_riscv_core.ForwardBE == 2'b10) forward_m_b_count++;
                if (dut.u_riscv_core.ForwardAE == 2'b01) forward_w_a_count++;
                if (dut.u_riscv_core.ForwardBE == 2'b01) forward_w_b_count++;
            end

            if (dut.u_riscv_core.u_datapath.RegWriteW &&
                (dut.u_riscv_core.u_datapath.RdW != 5'd0) &&
                (((dut.u_riscv_core.u_datapath.RdW == dut.Rs1D) &&
                  dut.u_riscv_core.UsesRs1D) ||
                 ((dut.u_riscv_core.u_datapath.RdW == dut.Rs2D) &&
                  dut.u_riscv_core.UsesRs2D)))
                wb_decode_count++;

            if (dut.MemWriteM && dut.u_riscv_core.u_datapath.RegWriteW &&
                (dut.u_riscv_core.u_datapath.RdW != 5'd0) &&
                (dut.u_riscv_core.u_datapath.RdW == dut.Rs2M)) begin
                if (dut.StoreWriteDataM !== dut.u_riscv_core.u_datapath.ResultW)
                    $fatal(1, "FAIL: WB-to-MEM store bypass selected wrong data");
                store_bypass_count++;
            end

            // O par em 0xD0/0xD4 tem dependencia somente em STORE.rs2. Ele
            // deve prosseguir sem stall e ser corrigido pelo bypass tardio.
            if ((dut.PCE == LOAD_STORE_COPY_LOAD_PC) &&
                (dut.PCD == (LOAD_STORE_COPY_LOAD_PC + 32'd4))) begin
                if (dut.u_riscv_core.StallF || dut.u_riscv_core.StallD ||
                    !dut.u_riscv_core.MemWriteD)
                    $fatal(1, "FAIL: LOAD-to-STORE.rs2 did not remain stall-free");
                seen_load_store_no_stall = 1'b1;
            end

            if (dut.BranchE) begin
                if (dut.u_riscv_core.PCSrcE)
                    branch_taken_count++;
                else
                    branch_not_taken_count++;
            end

            if (dut.u_riscv_core.PCSrcE) begin
                if (!dut.u_riscv_core.FlushD || !dut.u_riscv_core.FlushE ||
                    dut.u_riscv_core.StallF || dut.u_riscv_core.StallD)
                    $fatal(1, "FAIL: redirect controls inconsistent at PC=%h", dut.PCE);
                redirect_count++;
            end

            // JAL com rd=ra identifica uma chamada. JALR x0,0(ra) identifica
            // um retorno segundo a convencao usada pelo programa.
            if (dut.JumpE && !dut.JalrE && dut.RegWriteE && (dut.RdE == 5'd1))
                call_count++;
            if (dut.JalrE && (dut.RdE == 5'd0) && (dut.Rs1E == 5'd1))
                return_count++;

            if (dut.JumpE && !dut.JalrE && (dut.RdE == 5'd1) &&
                (dut.PCTargetE == BINARY_SEARCH_PC)) begin
                recursion_depth++;
                binary_call_count++;
                if (recursion_depth > max_recursion_depth)
                    max_recursion_depth = recursion_depth;
            end
            if (dut.JalrE && (dut.RdE == 5'd0) && (dut.Rs1E == 5'd1) &&
                (dut.PCE >= BINARY_SEARCH_PC) &&
                (dut.PCE < BINARY_SEARCH_END_PC))
                recursion_depth--;

            if ((dut.u_riscv_core.u_datapath.u_register_file.regs[2] != 0) &&
                (dut.u_riscv_core.u_datapath.u_register_file.regs[2] < min_sp))
                min_sp = dut.u_riscv_core.u_datapath.u_register_file.regs[2];

            if (dut.StoreEnableM && (dut.ALUResultM >= STACK_LOW) &&
                (dut.ALUResultM <= STACK_HIGH)) begin
                stack_write_count++;
                if (dut.ALUResultM < min_stack_address)
                    min_stack_address = dut.ALUResultM;
            end
            if (dut.LoadEnableM && (dut.ALUResultM >= STACK_LOW) &&
                (dut.ALUResultM <= STACK_HIGH)) begin
                stack_read_count++;
                if (dut.ALUResultM < min_stack_address)
                    min_stack_address = dut.ALUResultM;
            end
        end
    end

    // ------------------------------------------------------------
    // 5. Diagnostico e checagem final
    // ------------------------------------------------------------
    task automatic show_diagnostic(input string reason);
        begin
            $display("FAIL: %s", reason);
            $display("  cycles=%0d status=%h error=%h", cycle_count,
                     physical_word(32'h1f0), physical_word(32'h1f4));
            $display("  PCF=%h PCD=%h PCE=%h sp=%h ra=%h",
                     dut.PCF, dut.PCD, dut.PCE,
                     dut.u_riscv_core.u_datapath.u_register_file.regs[2],
                     dut.u_riscv_core.u_datapath.u_register_file.regs[1]);
            $display("  RegWriteW=%b RdW=%0d ResultW=%h ALUResultM=%h",
                     dut.u_riscv_core.u_datapath.RegWriteW,
                     dut.u_riscv_core.u_datapath.RdW,
                     dut.u_riscv_core.u_datapath.ResultW, dut.ALUResultM);
        end
    endtask

    task automatic check_final_state;
        integer index;
        integer missing;
        begin
            expect_word(32'h180, 32'd20, "sum");
            expect_word(32'h184, 32'hffff_fffd, "minimum");
            expect_word(32'h188, 32'd12, "maximum");
            $display("PASS: sum/min/max results");

            expect_word(32'h194, 32'd11, "dot product");
            $display("PASS: signed software multiplication and dot product");

            expect_word(32'h100, 32'hffff_fffd, "sorted A[0]");
            expect_word(32'h104, 32'd4, "sorted A[1]");
            expect_word(32'h108, 32'd7, "sorted A[2]");
            expect_word(32'h10c, 32'd12, "sorted A[3]");
            $display("PASS: insertion sort result");

            expect_word(32'h18c, 32'd3, "binary search found");
            expect_word(32'h190, 32'hffff_ffff, "binary search missing");
            $display("PASS: recursive binary search found/missing");

            expect_word(32'h198, 32'd13, "byte checksum");
            $display("PASS: byte checksum");

            expect_word(32'h1b0, 32'h80ff_7f01, "SB byte lanes");
            expect_word(32'h1b4, 32'h8001_7fff, "SH halfword lanes");
            expect_word(32'h1a4, MEMORY_SIGNATURE, "memory signature");
            if ((physical_byte(32'h1b0) !== 8'h01) ||
                (physical_byte(32'h1b1) !== 8'h7f) ||
                (physical_byte(32'h1b2) !== 8'hff) ||
                (physical_byte(32'h1b3) !== 8'h80))
                $fatal(1, "FAIL: little-endian byte lane order");
            $display("PASS: byte/half load-store probe and little-endian lanes");

            expect_word(32'h19c, BRANCH_SIGNATURE, "branch signature");
            expect_word(32'h1a0, ALU_SIGNATURE, "ALU signature");
            expect_word(32'h1a8, PC_PROBE_AUIPC_PC, "AUIPC PC probe");
            expect_word(32'h1ac, 32'd20, "LOAD-to-STORE copy");
            $display("PASS: branch, ALU and AUIPC probes");

            expect_word(32'h120, 32'd2, "B[0]");
            expect_word(32'h124, 32'd5, "B[1]");
            expect_word(32'h128, 32'hffff_ffff, "B[2]");
            expect_word(32'h12c, 32'd6, "B[3]");
            $display("PASS: reference vectors initialized by software; B preserved");

            expect_word(32'h1f4, 32'b0, "error code");
            expect_word(32'h1f8, 32'h0000_0800, "final sp snapshot");
            if ((dut.u_riscv_core.u_datapath.u_register_file.regs[2] !== 32'h800) ||
                (dut.u_riscv_core.u_datapath.u_register_file.regs[0] !== 32'b0))
                $fatal(1, "FAIL: final sp or x0 is incorrect");
            if ((stack_write_count == 0) || (stack_read_count == 0) ||
                (min_sp >= 32'h800) || (min_stack_address > STACK_HIGH))
                $fatal(1, "FAIL: real stack traffic was not observed");
            $display("PASS: stack restored; min_sp=%h min_access=%h writes=%0d reads=%0d",
                     min_sp, min_stack_address, stack_write_count, stack_read_count);

            if ((call_count < 10) || (return_count < 10) ||
                (binary_call_count < 4) || (max_recursion_depth < 3) ||
                (recursion_depth != 0))
                $fatal(1, "FAIL: nested calls/returns or real recursion not observed");
            $display("PASS: calls=%0d returns=%0d binary_calls=%0d recursion_depth=%0d",
                     call_count, return_count, binary_call_count,
                     max_recursion_depth);

            if (load_use_stall_count == 0)
                $fatal(1, "FAIL: no load-use stall observed");
            if ((store_bypass_count == 0) || !seen_load_store_no_stall)
                $fatal(1, "FAIL: WB-to-MEM store-data path not exercised");
            if ((forward_m_a_count == 0) || (forward_m_b_count == 0) ||
                (forward_w_a_count == 0) || (forward_w_b_count == 0) ||
                (wb_decode_count == 0))
                $fatal(1, "FAIL: one or more forwarding paths were not observed");
            $display("PASS: load-use=%0d store-bypass=%0d WB-decode=%0d",
                     load_use_stall_count, store_bypass_count, wb_decode_count);
            $display("PASS: forwarding M(A/B)=%0d/%0d W(A/B)=%0d/%0d",
                     forward_m_a_count, forward_m_b_count,
                     forward_w_a_count, forward_w_b_count);

            if ((branch_taken_count == 0) || (branch_not_taken_count == 0) ||
                (redirect_count == 0))
                $fatal(1, "FAIL: taken/not-taken control flow was not observed");
            $display("PASS: branches taken=%0d not_taken=%0d redirects=%0d",
                     branch_taken_count, branch_not_taken_count, redirect_count);

            missing = 0;
            for (index = 0; index < 37; index++) begin
                if (isa_seen[index])
                    $display("PASS ISA: %s executed", instruction_name(index));
                else begin
                    $display("FAIL ISA: %s was not executed", instruction_name(index));
                    missing++;
                end
            end
            if (missing != 0)
                $fatal(1, "FAIL: %0d supported instructions missing", missing);
            $display("PASS: all 37 supported instructions executed");
        end
    endtask

    // ------------------------------------------------------------
    // 6. Status, timeout e encerramento
    // ------------------------------------------------------------
    initial begin : test_sequence
        integer wait_cycles;
        logic [31:0] status;

        clk = 1'b0;
        reset = 1'b1;
        isa_seen = 37'b0;
        cycle_count = 0;
        load_use_stall_count = 0;
        forward_m_a_count = 0;
        forward_m_b_count = 0;
        forward_w_a_count = 0;
        forward_w_b_count = 0;
        store_bypass_count = 0;
        wb_decode_count = 0;
        branch_taken_count = 0;
        branch_not_taken_count = 0;
        redirect_count = 0;
        call_count = 0;
        return_count = 0;
        stack_write_count = 0;
        stack_read_count = 0;
        recursion_depth = 0;
        max_recursion_depth = 0;
        binary_call_count = 0;
        min_sp = 32'hffff_ffff;
        min_stack_address = 32'hffff_ffff;
        seen_load_store_no_stall = 1'b0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        // A DMEM nao possui reset: antes do primeiro SW do software, status
        // pode ser X. O laco ignora tanto X quanto zero e termina somente ao
        // observar uma palavra conhecida e nao nula escrita pelo programa.
        status = 32'hxxxx_xxxx;
        wait_cycles = 0;
        while ((wait_cycles < TIMEOUT_CYCLES) &&
               ((^status === 1'bx) || (status === 32'b0))) begin
            @(negedge clk);
            status = physical_word(32'h1f0);
            wait_cycles++;
        end

        if ((^status === 1'bx) || (status === 32'b0)) begin
            show_diagnostic("timeout waiting for final status");
            $fatal(1, "FAIL: timeout after %0d cycles", TIMEOUT_CYCLES);
        end
        if (status == FAIL_STATUS) begin
            show_diagnostic("software published FAIL status");
            $fatal(1, "FAIL: software error code=%0d", physical_word(32'h1f4));
        end
        if (status !== PASS_STATUS) begin
            show_diagnostic("unknown final status");
            $fatal(1, "FAIL: unexpected status=%h", status);
        end

        check_final_state();
        $display("PASS: RV32I system program completed in %0d cycles", cycle_count);
        $finish;
    end

endmodule
