`timescale 1ns/1ps

// Fecha os seis branches RV32I no pipeline completo. O teste observa a decisao
// em Execute, os flushes e os resultados arquiteturais sem escrever no RF.
module tb_branch;
    localparam integer PROGRAM_WORDS = 76;

    logic clk;
    logic reset;
    logic [31:0] expected_program [0:PROGRAM_WORDS-1];

    logic [31:7] limit_instr;
    logic [2:0]  limit_imm_src;
    logic [31:0] limit_imm_ext;
    logic [31:0] limit_encoding;

    integer taken_count [0:7];
    integer not_taken_count [0:7];
    integer branch_event_count;
    integer loop_branch_count;
    integer invalid_decode_count;
    integer invalid_execute_count;
    integer cycle_count;
    logic   double_forward_seen;
    logic   priority_seen;
    logic   wb_decode_seen;
    logic   wb_execute_seen;
    logic   x0_branch_seen;
    logic   done;

    wire        BranchD        = dut.u_riscv_core.BranchD;
    wire [2:0]  BranchControlD = dut.u_riscv_core.BranchControlD;
    wire [2:0]  BranchControlE = dut.u_riscv_core.u_datapath.BranchControlE;
    wire        BranchTakenE   = dut.u_riscv_core.u_datapath.BranchTakenE;
    wire        PCSrcE         = dut.u_riscv_core.PCSrcE;
    wire        FlushD         = dut.u_riscv_core.FlushD;
    wire        FlushE         = dut.u_riscv_core.FlushE;
    wire [1:0]  ForwardAE      = dut.u_riscv_core.ForwardAE;
    wire [1:0]  ForwardBE      = dut.u_riscv_core.ForwardBE;
    wire        RegWriteW      = dut.u_riscv_core.u_datapath.RegWriteW;
    wire [4:0]  RdW            = dut.u_riscv_core.u_datapath.RdW;
    wire [31:0] ResultW        = dut.u_riscv_core.u_datapath.ResultW;
    wire [31:0] RFRead1D       = dut.u_riscv_core.u_datapath.RFRead1D;
    wire [31:0] RFRead2D       = dut.u_riscv_core.u_datapath.RFRead2D;

    riscv_system_top #(
        .IMEM_INIT_FILE ("../mem/branch.hex")
    ) dut (
        .clk   (clk),
        .reset (reset)
    );

    // Instancia separada apenas para provar os dois limites do formato B sem
    // executar targets desalinhados ou fora da pequena IMEM deste projeto.
    extend u_limit_extend (
        .InstrD  (limit_instr),
        .ImmSrcD (limit_imm_src),
        .ImmExtD (limit_imm_ext)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    function automatic logic [31:0] encode_addi(
        input logic signed [11:0] immediate,
        input logic [4:0] rs1,
        input logic [4:0] rd
    );
        encode_addi = {immediate, rs1, 3'b000, rd, 7'b0010011};
    endfunction

    // Encoder independente do arquivo .hex. O offset em bytes e remontado nas
    // posicoes espalhadas do formato B e conserva o bit zero implicito.
    function automatic logic [31:0] encode_branch(
        input logic signed [12:0] offset,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3
    );
        encode_branch = {offset[12], offset[10:5], rs2, rs1, funct3,
                         offset[4:1], offset[11], 7'b1100011};
    endfunction

    task automatic set_addi(
        input integer index,
        input logic signed [11:0] immediate,
        input logic [4:0] rs1,
        input logic [4:0] rd
    );
        expected_program[index] = encode_addi(immediate, rs1, rd);
    endtask

    task automatic set_branch(
        input integer index,
        input logic signed [12:0] offset,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3
    );
        expected_program[index] = encode_branch(offset, rs2, rs1, funct3);
    endtask

    function automatic logic is_expected_branch(input logic [31:0] pc);
        case (pc)
            32'd8,   32'd32,  32'd40,  32'd56,
            32'd72,  32'd88,  32'd96,  32'd112,
            32'd120, 32'd136, 32'd152, 32'd160,
            32'd176, 32'd184, 32'd200, 32'd240,
            32'd268, 32'd292: is_expected_branch = 1'b1;
            default:          is_expected_branch = 1'b0;
        endcase
    endfunction

    function automatic logic is_static_not_taken(input logic [31:0] pc);
        case (pc)
            32'd32, 32'd56, 32'd88, 32'd112,
            32'd152, 32'd176: is_static_not_taken = 1'b1;
            default:          is_static_not_taken = 1'b0;
        endcase
    endfunction

    task automatic check_branch_execute;
        logic expected_taken;
        logic [31:0] expected_target;
        begin
            if (!is_expected_branch(dut.PCE))
                $fatal(1, "FAIL: branch inesperado em PCE=%0d", dut.PCE);

            expected_taken = !is_static_not_taken(dut.PCE);
            if (dut.PCE == 32'd292) begin
                case (loop_branch_count)
                    0, 1: expected_taken = 1'b1;
                    2:    expected_taken = 1'b0;
                    default: $fatal(1, "FAIL: loop executou branch em excesso");
                endcase
                if ((dut.SrcAE !== (32'd2 - loop_branch_count)) ||
                    (dut.WriteDataE !== 32'b0) || (ForwardAE !== 2'b10) ||
                    (ForwardBE !== 2'b00))
                    $fatal(1, "FAIL: branch backward nao recebeu contador forwarded");
                loop_branch_count = loop_branch_count + 1;
            end

            expected_target = (dut.PCE == 32'd292) ? 32'd288
                                                    : dut.PCE + 32'd12;

            if ((dut.RegWriteE !== 1'b0) || (dut.MemWriteE !== 1'b0) ||
                (dut.JumpE !== 1'b0) || (dut.JalrE !== 1'b0) ||
                (dut.ALUSrcE !== 1'b0) || (dut.ALUASrcE !== 1'b0) ||
                (dut.ALUControlE !== 4'b0001) ||
                (dut.SrcBE !== dut.WriteDataE) ||
                (dut.ALUResultE !== (dut.SrcAE - dut.WriteDataE)) ||
                (dut.ZeroE !== (dut.SrcAE == dut.WriteDataE)))
                $fatal(1, "FAIL: controles/ALU do branch em PCE=%0d", dut.PCE);

            if ((BranchTakenE !== expected_taken) ||
                (PCSrcE !== expected_taken) ||
                (FlushD !== expected_taken) || (FlushE !== expected_taken) ||
                (dut.PCTargetE !== expected_target) ||
                (dut.u_riscv_core.u_datapath.PCRelativeTargetE !== expected_target))
                $fatal(1, "FAIL: decisao/target do branch em PCE=%0d", dut.PCE);

            case (BranchControlE)
                3'b000: if (BranchTakenE !== dut.ZeroE)
                            $fatal(1, "FAIL: BEQ nao usou ZeroE");
                3'b001: if (BranchTakenE !== !dut.ZeroE)
                            $fatal(1, "FAIL: BNE nao usou ZeroE invertido");
                3'b100: if (BranchTakenE !==
                            ($signed(dut.SrcAE) < $signed(dut.WriteDataE)))
                            $fatal(1, "FAIL: BLT signed");
                3'b101: if (BranchTakenE !==
                            ($signed(dut.SrcAE) >= $signed(dut.WriteDataE)))
                            $fatal(1, "FAIL: BGE signed");
                3'b110: if (BranchTakenE !== (dut.SrcAE < dut.WriteDataE))
                            $fatal(1, "FAIL: BLTU unsigned");
                3'b111: if (BranchTakenE !== (dut.SrcAE >= dut.WriteDataE))
                            $fatal(1, "FAIL: BGEU unsigned");
                default: $fatal(1, "FAIL: BranchControlE reservado chegou ativo");
            endcase

            branch_event_count = branch_event_count + 1;
            if (expected_taken)
                taken_count[BranchControlE] = taken_count[BranchControlE] + 1;
            else
                not_taken_count[BranchControlE] =
                    not_taken_count[BranchControlE] + 1;

            // addi x1,7; addi x2,7; beq exercita W em A e M em B juntos.
            if (dut.PCE == 32'd8) begin
                if ((ForwardAE !== 2'b01) || (ForwardBE !== 2'b10) ||
                    (dut.SrcAE !== 32'd7) || (dut.WriteDataE !== 32'd7) ||
                    (dut.ZeroE !== 1'b1) || (BranchTakenE !== 1'b1) ||
                    (dut.PCD !== 32'd12) || (BranchD !== 1'b1))
                    $fatal(1, "FAIL: forwarding duplo ou branch younger no flush");
                double_forward_seen = 1'b1;
            end

            // M e W possuem x5; o valor 2 em M deve vencer o valor 1 em W.
            if (dut.PCE == 32'd240) begin
                if ((ForwardAE !== 2'b10) || (ForwardBE !== 2'b00) ||
                    (dut.SrcAE !== 32'd2) || (dut.WriteDataE !== 32'd2) ||
                    (dut.u_riscv_core.u_datapath.RdM !== 5'd5) ||
                    (dut.ALUResultM !== 32'd2) || (RdW !== 5'd5) ||
                    (ResultW !== 32'd1))
                    $fatal(1, "FAIL: prioridade M sobre W no branch");
                priority_seen = 1'b1;
            end

            if (dut.PCE == 32'd268) begin
                if ((ForwardAE !== 2'b00) || (ForwardBE !== 2'b00) ||
                    (dut.RD1E !== 32'd33) || (dut.RD2E !== 32'd33))
                    $fatal(1, "FAIL: branch nao preservou bypass WB->Decode");
                wb_execute_seen = 1'b1;
            end

            if (dut.PCE == 32'd200) begin
                if ((dut.SrcAE !== 32'b0) || (dut.WriteDataE !== 32'b0) ||
                    (ForwardAE !== 2'b00) || (ForwardBE !== 2'b00) ||
                    (BranchTakenE !== 1'b1) ||
                    (dut.u_riscv_core.u_datapath.RegWriteM !== 1'b1) ||
                    (dut.u_riscv_core.u_datapath.RdM !== 5'd0) ||
                    (dut.ALUResultM !== 32'd123))
                    $fatal(1, "FAIL: beq x0,x0 ou dependencia falsa em x0");
                x0_branch_seen = 1'b1;
            end
        end
    endtask

    // Captura PCSrcE antes do flanco para conferir o conteudo que FlushE grava
    // no ID/EX nesse mesmo flanco. Depois de #1, os nonblockings ja assentaram.
    always @(posedge clk) begin
        logic redirect_at_edge;
        redirect_at_edge = PCSrcE;
        #1;

        if (reset) begin
            if ((dut.BranchE !== 1'b0) || (BranchControlE !== 3'b000) ||
                (BranchTakenE !== 1'b0) || (PCSrcE !== 1'b0))
                $fatal(1, "FAIL: reset dos controles de branch");
        end else begin
            cycle_count = cycle_count + 1;

            if (redirect_at_edge &&
                ((dut.BranchE !== 1'b0) || (BranchControlE !== 3'b000) ||
                 (BranchTakenE !== 1'b0) || (PCSrcE !== 1'b0)))
                $fatal(1, "FAIL: FlushE nao inseriu bolha segura");

            if ((dut.u_riscv_core.StallF !== 1'b0) ||
                (dut.u_riscv_core.StallD !== 1'b0))
                $fatal(1, "FAIL: branch criou stall inesperado");
            if ((ForwardAE === 2'b11) || (ForwardBE === 2'b11))
                $fatal(1, "FAIL: forwarding gerou codigo reservado");
            if ({FlushD, FlushE} !== {2{PCSrcE}})
                $fatal(1, "FAIL: flushes nao acompanham PCSrcE");
            if ((dut.MemWriteM !== 1'b0) || (dut.u_data_memory.en !== 1'b0) ||
                (dut.u_data_memory.wstrb !== 4'b0000))
                $fatal(1, "FAIL: branch acessou a DMEM");

            // x20..x31 aparecem somente em caminhos que devem ser descartados.
            if (RegWriteW && (RdW >= 5'd20))
                $fatal(1, "FAIL: instrucao wrong-path chegou ao WB em x%0d", RdW);

            if (dut.BranchE)
                check_branch_execute();
            else if (PCSrcE || dut.JumpE || dut.JalrE)
                $fatal(1, "FAIL: redirect nao pertencente a branch");

            // Os funct3 010/011 devem atravessar sem qualquer efeito.
            if ((dut.PCD == 32'd216) || (dut.PCD == 32'd224)) begin
                if ((dut.OpD !== 7'b1100011) || (BranchD !== 1'b0) ||
                    (BranchControlD !== 3'b000) ||
                    (dut.u_riscv_core.RegWriteD !== 1'b0) ||
                    (dut.u_riscv_core.MemWriteD !== 1'b0) ||
                    (dut.u_riscv_core.JumpD !== 1'b0))
                    $fatal(1, "FAIL: funct3 reservado ativo em Decode");
                invalid_decode_count = invalid_decode_count + 1;
            end
            if ((dut.PCE == 32'd216) || (dut.PCE == 32'd224)) begin
                if (dut.BranchE || BranchTakenE || PCSrcE || FlushD || FlushE ||
                    dut.RegWriteE || dut.MemWriteE)
                    $fatal(1, "FAIL: funct3 reservado causou efeito em Execute");
                invalid_execute_count = invalid_execute_count + 1;
            end

            // Em PC=268, o produtor de x9 esta em W e o branch em Decode.
            if (dut.PCD == 32'd268) begin
                if ((BranchD !== 1'b1) || (BranchControlD !== 3'b000) ||
                    (RegWriteW !== 1'b1) || (RdW !== 5'd9) ||
                    (ResultW !== 32'd33) || (dut.Rs1D !== 5'd9) ||
                    (dut.Rs2D !== 5'd9) || (RFRead1D !== 32'd14) ||
                    (RFRead2D !== 32'd14) || (dut.RD1D !== 32'd33) ||
                    (dut.RD2D !== 32'd33))
                    $fatal(1, "FAIL: bypass WB->Decode para branch");
                wb_decode_seen = 1'b1;
            end

            if (RegWriteW && (RdW == 5'd14) && (ResultW == 32'd20))
                done = 1'b1;
        end
    end

    initial begin
        reset = 1'b1;
        limit_imm_src = 3'b010;
        branch_event_count = 0;
        loop_branch_count = 0;
        invalid_decode_count = 0;
        invalid_execute_count = 0;
        cycle_count = 0;
        double_forward_seen = 1'b0;
        priority_seen = 1'b0;
        wb_decode_seen = 1'b0;
        wb_execute_seen = 1'b0;
        x0_branch_seen = 1'b0;
        done = 1'b0;

        for (integer i = 0; i < 8; i = i + 1) begin
            taken_count[i] = 0;
            not_taken_count[i] = 0;
        end
        for (integer i = 0; i < PROGRAM_WORDS; i = i + 1)
            expected_program[i] = encode_addi(12'sd0, 5'd0, 5'd0);

        set_addi(0,  12'sd7,  5'd0,  5'd1);
        set_addi(1,  12'sd7,  5'd0,  5'd2);
        set_branch(2,  13'sd12, 5'd2, 5'd1, 3'b000);
        set_branch(3,  13'sd40, 5'd0, 5'd0, 3'b000);
        set_addi(4,  12'sd1,  5'd0,  5'd20);
        set_addi(5,  12'sd1,  5'd0,  5'd3);
        set_addi(6,  12'sd1,  5'd0,  5'd1);
        set_addi(7,  12'sd2,  5'd0,  5'd2);
        set_branch(8,  13'sd12, 5'd2, 5'd1, 3'b000);
        set_addi(9,  12'sd11, 5'd0,  5'd4);
        set_branch(10, 13'sd12, 5'd2, 5'd1, 3'b001);
        set_addi(11, 12'sd2,  5'd0,  5'd20);
        set_addi(12, 12'sd2,  5'd0,  5'd21);
        set_addi(13, 12'sd12, 5'd0,  5'd5);
        set_branch(14, 13'sd12, 5'd1, 5'd1, 3'b001);
        set_addi(15, 12'sd13, 5'd0,  5'd6);
        set_addi(16, -12'sd1, 5'd0, 5'd7);
        set_addi(17, 12'sd1,  5'd0,  5'd8);
        set_branch(18, 13'sd12, 5'd8, 5'd7, 3'b100);
        set_addi(19, 12'sd3,  5'd0,  5'd22);
        set_addi(20, 12'sd3,  5'd0,  5'd23);
        set_addi(21, 12'sd14, 5'd0,  5'd9);
        set_branch(22, 13'sd12, 5'd7, 5'd8, 3'b100);
        set_addi(23, 12'sd15, 5'd0,  5'd10);
        set_branch(24, 13'sd12, 5'd7, 5'd8, 3'b101);
        set_addi(25, 12'sd4,  5'd0,  5'd24);
        set_addi(26, 12'sd4,  5'd0,  5'd25);
        set_addi(27, 12'sd16, 5'd0,  5'd11);
        set_branch(28, 13'sd12, 5'd8, 5'd7, 3'b101);
        set_addi(29, 12'sd17, 5'd0,  5'd12);
        set_branch(30, 13'sd12, 5'd8, 5'd8, 3'b101);
        set_addi(31, 12'sd5,  5'd0,  5'd26);
        set_addi(32, 12'sd5,  5'd0,  5'd27);
        set_addi(33, 12'sd18, 5'd0,  5'd13);
        set_branch(34, 13'sd12, 5'd7, 5'd8, 3'b110);
        set_addi(35, 12'sd6,  5'd0,  5'd28);
        set_addi(36, 12'sd6,  5'd0,  5'd29);
        set_addi(37, 12'sd19, 5'd0,  5'd14);
        set_branch(38, 13'sd12, 5'd8, 5'd7, 3'b110);
        set_addi(39, 12'sd20, 5'd0,  5'd15);
        set_branch(40, 13'sd12, 5'd8, 5'd7, 3'b111);
        set_addi(41, 12'sd7,  5'd0,  5'd30);
        set_addi(42, 12'sd7,  5'd0,  5'd31);
        set_addi(43, 12'sd21, 5'd0,  5'd16);
        set_branch(44, 13'sd12, 5'd7, 5'd8, 3'b111);
        set_addi(45, 12'sd22, 5'd0,  5'd17);
        set_branch(46, 13'sd12, 5'd8, 5'd8, 3'b111);
        set_addi(47, 12'sd8,  5'd0,  5'd20);
        set_addi(48, 12'sd8,  5'd0,  5'd21);
        set_addi(49, 12'sd123, 5'd0, 5'd0);
        set_branch(50, 13'sd12, 5'd0, 5'd0, 3'b000);
        set_addi(51, 12'sd9,  5'd0,  5'd22);
        set_addi(52, 12'sd9,  5'd0,  5'd23);
        set_addi(53, 12'sd24, 5'd0,  5'd19);
        set_branch(54, 13'sd12, 5'd0, 5'd0, 3'b010);
        set_addi(55, 12'sd1,  5'd3,  5'd3);
        set_branch(56, 13'sd12, 5'd0, 5'd0, 3'b011);
        set_addi(57, 12'sd1,  5'd4,  5'd4);
        set_addi(58, 12'sd1,  5'd0,  5'd5);
        set_addi(59, 12'sd2,  5'd0,  5'd5);
        set_branch(60, 13'sd12, 5'd2, 5'd5, 3'b000);
        set_addi(61, 12'sd10, 5'd0,  5'd24);
        set_addi(62, 12'sd10, 5'd0,  5'd25);
        set_addi(63, 12'sd1,  5'd6,  5'd6);
        set_addi(64, 12'sd33, 5'd0,  5'd9);
        set_addi(65, 12'sd1,  5'd10, 5'd10);
        set_addi(66, 12'sd1,  5'd11, 5'd11);
        set_branch(67, 13'sd12, 5'd9, 5'd9, 3'b000);
        set_addi(68, 12'sd11, 5'd0,  5'd26);
        set_addi(69, 12'sd11, 5'd0,  5'd27);
        set_addi(70, 12'sd1,  5'd12, 5'd12);
        set_addi(71, 12'sd3,  5'd0,  5'd5);
        set_addi(72, -12'sd1, 5'd5, 5'd5);
        set_branch(73, -13'sd4, 5'd0, 5'd5, 3'b001);
        set_addi(74, 12'sd42, 5'd0,  5'd13);
        set_addi(75, 12'sd1,  5'd14, 5'd14);

        #1;
        for (integer i = 0; i < PROGRAM_WORDS; i = i + 1) begin
            if (dut.u_instruction_memory.mem[i] !== expected_program[i])
                $fatal(1, "FAIL encoding word %0d: hex=%h expected=%h",
                       i, dut.u_instruction_memory.mem[i], expected_program[i]);
        end
        for (integer i = PROGRAM_WORDS; i < 512; i = i + 1)
            dut.u_instruction_memory.mem[i] = 32'h0000_0013;
        $display("PASS: branch program encodings checked independently");

        limit_encoding = encode_branch(13'sd4094, 5'd2, 5'd1, 3'b000);
        limit_instr = limit_encoding[31:7];
        #1;
        if (limit_imm_ext !== 32'h0000_0ffe)
            $fatal(1, "FAIL: B-immediate +4094 = %h", limit_imm_ext);
        limit_encoding = encode_branch(-13'sd4096, 5'd2, 5'd1, 3'b000);
        limit_instr = limit_encoding[31:7];
        #1;
        if (limit_imm_ext !== 32'hffff_f000)
            $fatal(1, "FAIL: B-immediate -4096 = %h", limit_imm_ext);
        $display("PASS: B-immediate limits +4094 and -4096");

        @(posedge clk);
        #2;
        @(negedge clk);
        reset = 1'b0;

        wait (done);
        @(posedge clk);
        #2;

        if (branch_event_count != 20)
            $fatal(1, "FAIL: quantidade de branches executados = %0d",
                   branch_event_count);
        if ((taken_count[0] != 4) || (not_taken_count[0] != 1) ||
            (taken_count[1] != 3) || (not_taken_count[1] != 2) ||
            (taken_count[4] != 1) || (not_taken_count[4] != 1) ||
            (taken_count[5] != 2) || (not_taken_count[5] != 1) ||
            (taken_count[6] != 1) || (not_taken_count[6] != 1) ||
            (taken_count[7] != 2) || (not_taken_count[7] != 1))
            $fatal(1, "FAIL: matriz taken/not-taken incompleta");
        if ((taken_count[2] != 0) || (not_taken_count[2] != 0) ||
            (taken_count[3] != 0) || (not_taken_count[3] != 0) ||
            (invalid_decode_count != 2) || (invalid_execute_count != 2))
            $fatal(1, "FAIL: funct3 reservados nao ficaram inativos");
        if ((loop_branch_count != 3) || !double_forward_seen || !priority_seen ||
            !wb_decode_seen || !wb_execute_seen || !x0_branch_seen)
            $fatal(1, "FAIL: cobertura estrutural de branch incompleta");

        if ((dut.u_riscv_core.u_datapath.u_register_file.regs[1]  !== 32'd1) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[2]  !== 32'd2) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[3]  !== 32'd2) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[4]  !== 32'd12) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[5]  !== 32'd0) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[6]  !== 32'd14) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[7]  !== 32'hffff_ffff) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[8]  !== 32'd1) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[9]  !== 32'd33) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[10] !== 32'd16) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[11] !== 32'd17) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[12] !== 32'd18) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[13] !== 32'd42) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[14] !== 32'd20) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[15] !== 32'd20) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[16] !== 32'd21) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[17] !== 32'd22) ||
            (dut.u_riscv_core.u_datapath.u_register_file.regs[19] !== 32'd24))
            $fatal(1, "FAIL: estado arquitetural final dos branches");
        $display("PASS: BEQ/BNE/BLT/BGE/BLTU/BGEU taken and not-taken");
        $display("PASS: signed/unsigned, equality, x0 and reserved funct3");
        $display("PASS: dual forwarding, M priority and WB-Decode bypass");
        $display("PASS: forward redirects and finite backward branch loop");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "FAIL: branch test timeout");
    end

endmodule
