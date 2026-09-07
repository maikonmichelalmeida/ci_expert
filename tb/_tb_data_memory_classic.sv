`timescale 1ns/1ps

module tb_data_memory_classic;
    logic clk;
    logic en;
    logic [31:0] addr;
    logic [31:0] wdata;
    logic [3:0] wstrb;
    logic [31:0] rdata;

    data_memory dut (
        .clk   (clk),
        .en    (en),
        .addr  (addr),
        .wdata (wdata),
        .wstrb (wstrb),
        .rdata (rdata)
    );

    always #5 clk = ~clk;

    task automatic write_word (
        input logic [31:0] address,
        input logic [31:0] data
    );
        begin
            @(negedge clk);
            en    = 1'b1;
            addr  = address;
            wdata = data;
            wstrb = 4'b1111;
            @(posedge clk);
            #1;
            wstrb = 4'b0000;
        end
    endtask

    initial begin
        clk   = 1'b0;
        en    = 1'b0;
        addr  = 32'b0;
        wdata = 32'b0;
        wstrb = 4'b0000;

        // Cria duas palavras conhecidas usando somente a porta normal da DMEM.
        write_word(32'h0000_0040, 32'h1122_3344);
        write_word(32'h0000_0044, 32'h5566_7788);

        // A) O novo dado ainda nao pode aparecer antes do posedge de escrita.
        @(negedge clk);
        en    = 1'b1;
        addr  = 32'h0000_0040;
        wdata = 32'hdead_beef;
        wstrb = 4'b1111;
        #1;
        if (rdata !== 32'h1122_3344)
            $fatal(1, "FAIL: DMEM write occurred before posedge");
        @(posedge clk);
        #1;
        if (rdata !== 32'hdead_beef)
            $fatal(1, "FAIL: DMEM write did not occur at posedge");
        wstrb = 4'b0000;
        $display("PASS: DMEM write remains synchronous");

        // B) Troca somente addr, sem clock entre as duas leituras.
        addr = 32'h0000_0040;
        #1;
        if (rdata !== 32'hdead_beef)
            $fatal(1, "FAIL: combinational read of word A");
        addr = 32'h0000_0044;
        #1;
        if (rdata !== 32'h5566_7788)
            $fatal(1, "FAIL: rdata waited for a clock after address change");
        $display("PASS: DMEM read follows addr combinationally");

        // Uma escrita parcial confirma que os quatro byte banks e wstrb foram
        // preservados durante a separacao entre leitura e escrita.
        @(negedge clk);
        addr  = 32'h0000_0044;
        wdata = 32'h00aa_0000;
        wstrb = 4'b0100;
        @(posedge clk);
        #1;
        wstrb = 4'b0000;
        if (rdata !== 32'h55aa_7788)
            $fatal(1, "FAIL: byte lane 2 or little-endian order changed");
        $display("PASS: byte lanes and wstrb remain functional");

        // C) en=0 zera a leitura e bloqueia a escrita mesmo com strobes ativos.
        @(negedge clk);
        en    = 1'b0;
        addr  = 32'h0000_0044;
        wdata = 32'hffff_ffff;
        wstrb = 4'b1111;
        #1;
        if (rdata !== 32'b0)
            $fatal(1, "FAIL: en=0 did not drive rdata to zero");
        @(posedge clk);
        #1;
        en    = 1'b1;
        wstrb = 4'b0000;
        #1;
        if (rdata !== 32'h55aa_7788)
            $fatal(1, "FAIL: en=0 allowed a write");
        $display("PASS: en=0 disables read and write");

        $display("PASS: classic DMEM timing test completed");
        $finish;
    end

endmodule
