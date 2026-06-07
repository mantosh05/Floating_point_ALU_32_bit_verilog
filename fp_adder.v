module fp_adder_subtractor(
    input  [31:0] a,
    input  [31:0] b,
    output reg [31:0] result
);

reg sign_a, sign_b;
reg sign_res;

reg [7:0] exp_a, exp_b;
reg [7:0] exp_res;
reg [7:0] exp_diff;

reg [22:0] frac_a, frac_b;

reg [26:0] mant_a, mant_b;
reg [26:0] mant_large, mant_small;

reg [27:0] add_sub_result;
reg [4:0]  shift_amt;
integer i;

// For Rounding
reg [22:0] final_frac;
reg guard_bit;
reg round_bit;
reg sticky_bit;
reg [27:0] rounded_mantissa;

always @(*) begin
    // 1. Unpack the inputs
    sign_a = a[31];
    sign_b = b[31];
    exp_a  = a[30:23];
    exp_b  = b[30:23];
    frac_a = a[22:0];
    frac_b = b[22:0];

    // 2. Append Hidden Bit (27 bits total: 1-bit hidden, 23-bit fraction, 3-bit alignment padding)
    mant_a = (exp_a == 0) ? {1'b0, frac_a, 3'b000} : {1'b1, frac_a, 3'b000};
    mant_b = (exp_b == 0) ? {1'b0, frac_b, 3'b000} : {1'b1, frac_b, 3'b000};

    // 3. Exponent Alignment & Sticky Bit Extraction
    if (exp_a >= exp_b) begin
        exp_diff   = exp_a - exp_b;
        exp_res    = exp_a;
        mant_large = mant_a;
        
        // preserving sticky bit 
        mant_small = mant_b >> exp_diff;
        if (exp_diff == 0) 
            sticky_bit = 1'b0;
        else if (exp_diff >= 27)
            sticky_bit = |mant_b;
        else
            sticky_bit = |(mant_b << (27 - exp_diff)); // Checks dropped bits
    end 
    else begin
        exp_diff   = exp_b - exp_a;
        exp_res    = exp_b;
        mant_large = mant_b;
        
        mant_small = mant_a >> exp_diff;
        if (exp_diff == 0) 
            sticky_bit = 1'b0;
        else if (exp_diff >= 27)
            sticky_bit = |mant_a;
        else
            sticky_bit = |(mant_a << (27 - exp_diff));
    end

    // 4. Addition block
    if (sign_a == sign_b) begin
        add_sub_result = mant_large + mant_small;
        sign_res       = sign_a;

        // Handle Carry-out Overflow immediately
        if (add_sub_result[27]) begin
            sticky_bit     = sticky_bit | add_sub_result[0];
            add_sub_result = add_sub_result >> 1;
            exp_res        = exp_res + 1;
        end
    end else begin
        // Subtraction: Since mant_large is sorted by exponent magnitude, 
        // we must check if mantissa swap is needed when exponents are equal.
        if ((exp_a == exp_b) && (mant_b > mant_a)) begin
            add_sub_result = mant_small - mant_large; // mant_b - mant_a
            sign_res       = sign_b;
        end else begin
            add_sub_result = mant_large - mant_small;
            sign_res       = sign_a;
        end

        // 5. Normalization (Leading Zero Detector) for Subtraction
        shift_amt = 5'd27; 
        for (i = 0; i < 28; i = i + 1) begin
            if (add_sub_result[i]) begin
                shift_amt = 26 - i; // Find distance to bring MSB to bit[26]
            end
        end

        if (add_sub_result != 0 && exp_res > shift_amt) begin
            add_sub_result = add_sub_result << shift_amt;
            exp_res        = exp_res - shift_amt;
        end else if (add_sub_result != 0) begin
            // Underflow handling to subnormal domain
            add_sub_result = add_sub_result << (exp_res - 1);
            exp_res        = 8'h0;
        end
    end

    // 6. Round-to-Nearest-Even Setup
    guard_bit  = add_sub_result[2];
    round_bit  = add_sub_result[1];
    sticky_bit = sticky_bit | add_sub_result[0]; // Combine with historical shift data

    rounded_mantissa = add_sub_result;

    // Apply Rounding Condition
    if (guard_bit && (round_bit || sticky_bit || add_sub_result[3])) begin
        rounded_mantissa = add_sub_result + 28'h8; // Add 1 to the units place (bit 3)
        
        // Check if rounding caused an overflow
        if (rounded_mantissa[27]) begin
            rounded_mantissa = rounded_mantissa >> 1;
            exp_res          = exp_res + 1;
        end
    end

    // 7. Exceptional Cases & Final Packaging
    if (a[30:0] == 0 && b[30:0] == 0 && (sign_a != sign_b)) begin
        result = 32'b0; // (+0) + (-0) = +0
    end else if (add_sub_result == 0) begin
        result = 32'b0;
    end else if (exp_res >= 8'hFF) begin
        result = {sign_res, 8'hFF, 23'b0}; // Overflow to Infinity
    end else if (exp_res == 0) begin
        result = {sign_res, 8'h00, rounded_mantissa[25:3]}; // Subnormal handling
    end else begin
        result = {sign_res, exp_res, rounded_mantissa[25:3]}; // Normal packing
    end
end

endmodule