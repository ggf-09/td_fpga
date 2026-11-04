
`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: anlgoic
// Author: 	xg 
// description: sdram init and refresh
//////////////////////////////////////////////////////////////////////////////////

`define signle_bit 0

`include "global_def.v"

module sdr_init_ref #( parameter self_refresh_open=1
			)
	(
	    input   		Sdr_clk,
        input   		Rst,
			  			  
		////change sdr work mode
		input			Sdr_init_req,
        input	[3:0]	Sdr_init_mode, ////[2:0]: Burst Lenth, [3]:M9 ,1=sigle write
		output 			Sdr_init_done,
		
		////check wrtie and read busy	
		input			App_ref_req,	
		output			Sdr_ref_req,	//it must have 4096 refersh command in 64ms,send 1 time in 15.625ms
		input			Sdr_ref_ack,
		input			Sdr_rw_vld,

		output			Sdr_init_ref_vld,
        output			Sdr_init_ref_ras,
		output			Sdr_init_ref_cas,
		output			Sdr_init_ref_we,
		output	[`BA_WIDTH-1:0]	Sdr_init_ref_ba,
		output	[`ROW_WIDTH:0]	Sdr_init_ref_addr
	);


reg		[17:0]	pwr_200ms_cnt;
reg 			power_up_200ms_1d,power_up_200ms_2d,power_up_en;

reg 			sdr_init_en;
reg 	[31:0]	sdr_init_cnt=32'd0;
reg 			init_vld,init_done;
reg		[13:0]	init_cnt;
reg		[19:0]	sdr_ref_ack_sft;
reg				ref_req,ref_vld;

reg 					ras,cas,we;
reg 	[`ROW_WIDTH:0]	ad;
reg						cke;


//pipe
always @(posedge Sdr_clk)
begin
	if(Rst)
		pwr_200ms_cnt <= 17'd0;
	else if(pwr_200ms_cnt[17])
		pwr_200ms_cnt <= pwr_200ms_cnt;
	else
		pwr_200ms_cnt <= pwr_200ms_cnt+1'b1;
	
	power_up_200ms_1d <= pwr_200ms_cnt[17];
	power_up_200ms_2d <= power_up_200ms_1d;
	power_up_en <= power_up_200ms_1d & (!power_up_200ms_2d);
	
	sdr_init_en <= power_up_en | Sdr_init_req;
end

//sdr init cnt
always @(posedge Sdr_clk)
begin  
  		sdr_init_cnt[0]<= sdr_init_en;	
		sdr_init_cnt[31:1]<=sdr_init_cnt[30:0];
end	

always @(posedge Sdr_clk)
begin  
	if (sdr_init_cnt[30] || Rst)     ////valid 15 clk
        init_vld <= 1'b0;   
	else if (sdr_init_cnt[0]) 
	    init_vld <= 1'b1;
end
always @(posedge Sdr_clk)
begin  
	if (sdr_init_en || Rst)
	    init_done <= 1'b0;
	else if (sdr_init_cnt[30])
	    init_done <= 1'b1;
end
assign Sdr_init_ref_vld = init_vld || ref_vld;	
assign Sdr_init_done = init_done;


////init cunt
always @(posedge Sdr_clk)
begin  
	if (Rst || (!init_done))
        init_cnt <= 14'd0;   
	else
		if(init_cnt==`SELF_REFRESH_INTERVAL)
			init_cnt <= 14'd0;
		else
			init_cnt <= init_cnt+1'b1;
end

////ref ack shift
always @(posedge Sdr_clk)
begin  
	if (Rst)
		sdr_ref_ack_sft <= 'd0;
	else
		begin
			sdr_ref_ack_sft[0]	<= Sdr_ref_ack;
			sdr_ref_ack_sft[19:1]	<= sdr_ref_ack_sft[18:0];
		end
end


////self refresh
always @(posedge Sdr_clk)
begin  
	if (Rst)
		begin
			ref_req <= 1'd0;   
			ref_vld <= 1'b0;
		end
	else begin
		if(self_refresh_open)
			if(init_cnt==(`SELF_REFRESH_INTERVAL-10) && (!Sdr_ref_ack))	////if previous ack allign current ref req
				ref_req <= 1'b1;
			else
				ref_req <= 1'b0;
		else
			ref_req <= 1'b0;

			
		if(Sdr_ref_ack && (~Sdr_rw_vld))
			ref_vld <= 1'b1;
		else if(sdr_ref_ack_sft[19])
			ref_vld <= 1'b0;
	
	end
end
assign Sdr_ref_req=ref_req | App_ref_req;



endmodule
