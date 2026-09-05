`timescale 1ns/1ps

module tb_memories;

    logic        clk;
    logic        imem_en;
    logic [31:0] imem_addr;
    logic [31:0] imem_rdata;
    logic        dmem_en;
    logic [31:0] dmem_addr;
    logic [31:0] dmem_wdata;
    logic [3:0]  dmem_wstrb;
    logic [31:0] dmem_rdata;

    instruction_memory #(
        .MEM_BYTES (2048),
        .INIT_FILE ("../mem/program.hex")
    ) u_instruction_memory (
        .clk   (clk),
        .en    (imem_en),
        .addr  (imem_addr),
        .rdata (imem_rdata)
    );

    data_memory #(
        .MEM_BYTES (2048)
    ) u_data_memory (
        .clk   (clk),
        .en    (dmem_en),
        .addr  (dmem_addr),
        .wdata (dmem_wdata),
        .wstrb (dmem_wstrb),
        .rdata (dmem_rdata)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic check_imem (
        input logic [31:0] address,
        input logic [31:0] expected,
        input logic [31:0] previous,
        input logic        check_previous
    );
        begin
            @(negedge clk);
            imem_en   = 1'b1;
            imem_addr = address;
            #1;

            // Antes do proximo clock, a saida ainda deve guardar a leitura anterior.
            if (check_previous && (imem_rdata !== previous)) begin
                $fatal(1, "FAIL IMEM latency: rdata=%h expected_previous=%h",
                       imem_rdata, previous);
            end

            @(posedge clk);
            #1;
            if (imem_rdata !== expected) begin
                $fatal(1, "FAIL IMEM address=%h rdata=%h expected=%h",
                       address, imem_rdata, expected);
            end

            $display("PASS IMEM: address=%h rdata=%h", address, imem_rdata);
        end
    endtask

    task automatic write_dmem (
        input logic        access_enable,
        input logic [31:0] address,
        input logic [31:0] data,
        input logic [3:0]  strobes
    );
        begin
            @(negedge clk);
            dmem_en    = access_enable;
            dmem_addr  = address;
            dmem_wdata = data;
            dmem_wstrb = strobes;
            @(posedge clk);
            #1;
            dmem_en    = 1'b0;
            dmem_wstrb = 4'b0000;
        end
    endtask

    task automatic check_dmem (
        input logic [31:0] address,
        input logic [31:0] expected,
        input logic [31:0] previous,
        input logic        check_previous
    );
        begin
            @(negedge clk);
            dmem_en    = 1'b1;
            dmem_addr  = address;
            dmem_wstrb = 4'b0000;
            #1;

            // A mudanca de endereco nao altera rdata antes do proximo clock.
            if (check_previous && (dmem_rdata !== previous)) begin
                $fatal(1, "FAIL DMEM latency: rdata=%h expected_previous=%h",
                       dmem_rdata, previous);
            end

            @(posedge clk);
            #1;
            if (dmem_rdata !== expected) begin
                $fatal(1, "FAIL DMEM address=%h rdata=%h expected=%h",
                       address, dmem_rdata, expected);
            end

            dmem_en = 1'b0;
            $display("PASS DMEM: address=%h rdata=%h", address, dmem_rdata);
        end
    endtask

    initial begin
        imem_en    = 1'b0;
        imem_addr  = 32'b0;
        dmem_en    = 1'b0;
        dmem_addr  = 32'b0;
        dmem_wdata = 32'b0;
        dmem_wstrb = 4'b0000;

        $display("=== INSTRUCTION MEMORY TEST ===");
        check_imem(32'h0000_0000, 32'h0010_0093, 32'b0,         1'b0);
        check_imem(32'h0000_0004, 32'h0020_0113, 32'h0010_0093, 1'b1);
        check_imem(32'h0000_0008, 32'h0020_81b3, 32'h0020_0113, 1'b1);

        @(negedge clk);
        imem_en   = 1'b0;
        imem_addr = 32'h0000_0000;
        @(posedge clk);
        #1;
        if (imem_rdata !== 32'h0020_81b3) begin
            $fatal(1, "FAIL IMEM enable: rdata changed while en=0");
        end
        $display("PASS IMEM: en=0 keeps the previous output");

        $display("=== DATA MEMORY TEST ===");

        // Palavra completa em uma posicao.
        write_dmem(1'b1, 32'h0000_0000, 32'h1122_3344, 4'b1111);
        check_dmem(32'h0000_0000, 32'h1122_3344, 32'b0, 1'b0);

        // Somente o byte 1 deve mudar.
        write_dmem(1'b1, 32'h0000_0000, 32'h0000_aa00, 4'b0010);
        check_dmem(32'h0000_0000, 32'h1122_aa44, 32'b0, 1'b0);

        // Somente os bytes 2 e 3 devem mudar.
        write_dmem(1'b1, 32'h0000_0000, 32'hbeef_0000, 4'b1100);
        check_dmem(32'h0000_0000, 32'hbeef_aa44, 32'b0, 1'b0);

        // wstrb zerado nao pode alterar a palavra.
        write_dmem(1'b1, 32'h0000_0000, 32'hdead_beef, 4'b0000);
        check_dmem(32'h0000_0000, 32'hbeef_aa44, 32'b0, 1'b0);

        // Usa a ultima palavra dos 2 KiB para conferir o indice do endereco.
        write_dmem(1'b1, 32'h0000_07fc, 32'h5566_7788, 4'b1111);
        check_dmem(32'h0000_0000, 32'hbeef_aa44, 32'b0,         1'b0);
        check_dmem(32'h0000_07fc, 32'h5566_7788, 32'hbeef_aa44, 1'b1);

        // Mesmo com strobes ativos, en=0 deve impedir a escrita.
        write_dmem(1'b0, 32'h0000_07fc, 32'hffff_ffff, 4'b1111);
        check_dmem(32'h0000_07fc, 32'h5566_7788, 32'b0, 1'b0);

        $display("PASS: all instruction and data memory tests completed");
        $display("=== TEST FINISHED ===");
        $finish;
    end

endmodule
