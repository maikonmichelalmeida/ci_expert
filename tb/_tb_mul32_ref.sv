`timescale 1ns/1ps

// Testbench independente do processador para o multiplicador de referencia.
module tb_mul32_ref;

    localparam integer RANDOM_CASES = 1000;

    logic        clk;
    logic        reset;
    logic [31:0] a;
    logic [31:0] b;
    logic [63:0] p;

    logic [63:0] expected_stage1;
    logic [63:0] expected_stage2;
    logic [31:0] operand_a_stage1;
    logic [31:0] operand_a_stage2;
    logic [31:0] operand_b_stage1;
    logic [31:0] operand_b_stage2;
    logic        valid_stage1;
    logic        valid_stage2;

    integer seed;
    integer random_seed;
    integer cycle_count;
    integer sent_count;
    integer checked_count;
    integer random_index;
    logic [31:0] random_a;
    logic [31:0] random_b;

    mul32_ref dut (
        .clk   (clk),
        .reset (reset),
        .a     (a),
        .b     (b),
        .p     (p)
    );

    // A extensao explicita preserva todos os 64 bits do produto de referencia.
    function automatic logic [63:0] reference_product (
        input logic [31:0] operand_a,
        input logic [31:0] operand_b
    );
        logic [63:0] operand_a_64;
        logic [63:0] operand_b_64;
        begin
            operand_a_64     = {32'b0, operand_a};
            operand_b_64     = {32'b0, operand_b};
            reference_product = operand_a_64 * operand_b_64;
        end
    endfunction

    // A pequena fila de duas etapas acompanha os dois bancos de registradores:
    // entrada -> multiplicacao combinacional -> saida. Um novo caso ainda pode
    // ser enviado a cada ciclo, e o resultado e conferido sem delays arbitrarios.
    task automatic advance_scoreboard (
        input logic        issue_valid,
        input logic [31:0] next_a,
        input logic [31:0] next_b
    );
        begin
            @(negedge clk);
            cycle_count = cycle_count + 1;

            if (valid_stage2) begin
                if (p !== expected_stage2) begin
                    $fatal(1,
                        "FAIL: a=%h b=%h expected=%h obtained=%h cycle=%0d",
                        operand_a_stage2, operand_b_stage2,
                        expected_stage2, p, cycle_count);
                end
                checked_count = checked_count + 1;
            end

            expected_stage2  = expected_stage1;
            operand_a_stage2 = operand_a_stage1;
            operand_b_stage2 = operand_b_stage1;
            valid_stage2     = valid_stage1;

            if (issue_valid) begin
                a                = next_a;
                b                = next_b;
                expected_stage1  = reference_product(next_a, next_b);
                operand_a_stage1 = next_a;
                operand_b_stage1 = next_b;
                valid_stage1     = 1'b1;
                sent_count       = sent_count + 1;
            end else begin
                a            = 32'b0;
                b            = 32'b0;
                valid_stage1 = 1'b0;
            end
        end
    endtask

    always #5 clk = ~clk;

    initial begin
`ifdef VCS
        $fsdbDumpfile("test.fsdb");
        $fsdbDumpvars(0, tb_mul32_ref);
`endif

        clk              = 1'b0;
        reset            = 1'b1;
        a                = 32'b0;
        b                = 32'b0;
        expected_stage1  = 64'b0;
        expected_stage2  = 64'b0;
        operand_a_stage1 = 32'b0;
        operand_a_stage2 = 32'b0;
        operand_b_stage1 = 32'b0;
        operand_b_stage2 = 32'b0;
        valid_stage1     = 1'b0;
        valid_stage2     = 1'b0;
        cycle_count      = 0;
        sent_count       = 0;
        checked_count    = 0;

        if ($value$plusargs("SEED=%d", seed) == 0) begin
            seed = 32'h32c0_ffee;
        end
        random_seed = seed;

        repeat (2) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        // Casos dirigidos de zero, limites e padroes alternados.
        advance_scoreboard(1'b1, 32'h0000_0000, 32'h0000_0000);
        advance_scoreboard(1'b1, 32'h0000_0000, 32'h1234_5678);
        advance_scoreboard(1'b1, 32'h0000_0001, 32'h1234_5678);
        advance_scoreboard(1'b1, 32'h0000_0002, 32'h0000_0002);
        advance_scoreboard(1'b1, 32'hffff_ffff, 32'h0000_0001);
        advance_scoreboard(1'b1, 32'hffff_ffff, 32'h0000_0002);
        advance_scoreboard(1'b1, 32'hffff_ffff, 32'hffff_ffff);
        advance_scoreboard(1'b1, 32'h8000_0000, 32'h0000_0002);
        advance_scoreboard(1'b1, 32'haaaa_aaaa, 32'h5555_5555);

        for (random_index = 0; random_index < RANDOM_CASES; random_index++) begin
            random_a = $urandom(random_seed);
            random_b = $urandom(random_seed);
            advance_scoreboard(1'b1, random_a, random_b);
        end

        // Dois ciclos sem nova entrada esvaziam as duas etapas do scoreboard.
        advance_scoreboard(1'b0, 32'b0, 32'b0);
        advance_scoreboard(1'b0, 32'b0, 32'b0);

        if (checked_count != sent_count) begin
            $fatal(1, "FAIL: sent=%0d checked=%0d", sent_count, checked_count);
        end

        $display(
            "PASS: mul32_ref completed %0d cases, seed=%0d, latency=1 cycle after input capture",
            checked_count, seed);
        $finish;
    end

endmodule
