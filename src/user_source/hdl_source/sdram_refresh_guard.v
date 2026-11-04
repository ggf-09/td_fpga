`timescale 1ns/1ps

// Own refresh scheduling so that the controller never refreshes in the
// middle of an unbackpressured 128-word application burst. New bursts wait
// on hold_new_bursts; bursts already started and their return pipelines drain.
module sdram_refresh_guard #(
    parameter integer INTERVAL_CYCLES = 1953,
    parameter integer QUIET_CYCLES = 32,
    parameter integer TIMEOUT_CYCLES = 1024
) (
    input wire clk, rst_n, init_done,
    input wire rd_active, wr_active, app_rd_en, app_wr_en,
    input wire refresh_active,
    output wire hold_new_bursts,
    output reg app_ref_req,
    output reg fault
);
    localparam IDLE=0, DRAIN=1, WAIT_BEGIN=2, WAIT_END=3, SETTLE=4, FAULT=5;
    reg [2:0] state;
    reg [11:0] interval_count;
    reg [10:0] wait_count;
    reg [5:0] quiet_count;
    reg due_q;
    wire due = INTERVAL_CYCLES<=1 || due_q;
    wire traffic = rd_active || wr_active || app_rd_en || app_wr_en;
    assign hold_new_bursts = !init_done || state != IDLE || due || refresh_active;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; due_q<=0; interval_count<=0; wait_count<=0; quiet_count<=0;
            app_ref_req<=0; fault<=0;
        end else begin
            app_ref_req<=0;
            if (!init_done) begin
                state<=IDLE; due_q<=0; interval_count<=0; wait_count<=0; quiet_count<=0;
            end else begin
                if (!due) begin
                    interval_count<=interval_count+1'b1;
                    if(interval_count>=INTERVAL_CYCLES-2)due_q<=1;
                end
                if (state==IDLE) wait_count<=0;
                else if (state!=FAULT) begin
                    if (wait_count < TIMEOUT_CYCLES-1) wait_count<=wait_count+1'b1;
                    else begin state<=FAULT; fault<=1; end
                end
                // Timeout takes precedence over every state transition.
                if (state==IDLE || wait_count < TIMEOUT_CYCLES-1) case (state)
                    IDLE: if (due) begin state<=DRAIN; quiet_count<=0; end
                    DRAIN: begin
                        if (traffic || refresh_active) quiet_count<=0;
                        else if (quiet_count==QUIET_CYCLES-1) begin
                            app_ref_req<=1;
                            interval_count<=0;due_q<=0;
                            quiet_count<=0;
                            state<=WAIT_BEGIN;
                        end else quiet_count<=quiet_count+1'b1;
                    end
                    WAIT_BEGIN: if (refresh_active) state<=WAIT_END;
                    WAIT_END: if (!refresh_active) begin state<=SETTLE; quiet_count<=0; end
                    SETTLE: begin
                        if (quiet_count==QUIET_CYCLES-1) begin state<=IDLE; quiet_count<=0; end
                        else quiet_count<=quiet_count+1'b1;
                    end
                    FAULT: state<=FAULT;
                    default: begin state<=FAULT; fault<=1; end
                endcase
            end
        end
    end
endmodule
