####################################################
# Copyright(c) LUBIS EDA GmbH, All rights reserved #
# Contact: contact@lubis-eda.com                   #
####################################################

# TCL-script for VC Formal (Synopsys)

################################################################################
# Configuration

# Select what actions the tool should automatically perform
# Check:   When true  it          performs proofs for all properties of the default task
#          When false it does not perform  proofs for all properties of the default task
set auto_check 0
# Witness: When true  it          computes witnesses for all properties of the default task
#          When false it does not compute  witnesses for all properties of the default task
set auto_witness 0

# Tell the tool to exit after the execution of the tcl-script finishes
# When 1: Tool will exit
# When 0: Tool will remain in interactive mode
set exit_after_execution 0

# Select the way how VCF is informed about reset signals
# When 1: Tell VCF about reset signals and don't create a constraint that permanently disables them
# When 0: Tell VCF about reset signals and       create a constraint that permanently disables them
set reset_without_constraint 1

################################################################################
# Script - No change required below this line

# Change working directory to the directory of the script
# Eliminate every symbolic link
set script_path [file dirname [file normalize [info script]]]
cd $script_path


#################
# Configure VCF #
set_fml_appmode FPV
set_app_var apply_bind_in_all_units true
set_app_var analyze_skip_translate_body false
set_app_var fml_auto_save default
set_app_var fml_composite_trace true
set_fml_var fml_witness_on true
set_fml_var fml_vacuity_on true


###############
# Load Design #
cd $script_path
analyze -format sverilog -vcs " " {
    lubis_fifo.sv
}

cd $script_path

cd $script_path
analyze -format sverilog -vcs " -assert svaext +incdir+../rtl " {
    fv_scoreboard.sv
}

cd $script_path

elaborate lubis_fifo -verbose -sva

##########################
# Configure Verification #
create_clock clk -period 200

set_change_at -default -clock clk -posedge

# Problem (page 51 VC formal manual):
# Reset high, "create_reset rst -sense high" is the same as:
# sim_force rst -apply 1'b1
# set_constant rst -apply 1'b0
# This creates a constraint that sets reset to constant 0 which prevents any proofs
# that start from reset.
if {$reset_without_constraint} {
    sim_force rst -apply 1'b1
} else {
    create_reset rst -sense high
}


####################
# Check properties #
if {$auto_check && $auto_witness} {
    check_fv
} elseif {$auto_check} {
    check_fv
} elseif {$auto_witness} {
    check_fv -subtype witness
}

if {$exit_after_execution} {
    exit
}
