####################################################
# Copyright(c) LUBIS EDA GmbH, All rights reserved #
# Contact: contact@lubis-eda.com                   #
####################################################

# TCL-script for OneSpin (Siemens EDA)

################################################################################
# Configuration

# Tell the tool to use database (and create one unless it exists)
# When 1: Tool will     create &     load the database
# When 0: Tool will not create & not load the database
set use_setup_database 0

# Select what actions the tool should automatically perform
# Check:   When true  it          performs proofs for all properties of the default task
#          When false it does not perform  proofs for all properties of the default task
set auto_check 1
# Witness: When true  it          computes witnesses for all properties of the default task
#          When false it does not compute  witnesses for all properties of the default task
set auto_witness 0

# Tell the tool to exit after the execution of the tcl-script finishes
# When 1: Tool will exit
# When 0: Tool will remain in interactive mode
set exit_after_execution 0

################################################################################
# Script - No change required below this line

# Change working directory to the directory of the script
# Eliminate every symbolic link
set script_path [file dirname [file normalize [info script]]]
cd $script_path


# Start logging
start_message_log -force ./prove.log


# Re-run setup in case this script was already executed
#re_setup
set_mode setup
delete_design -both
remove_server -all

set_session_option -naming_style sv


# Load Setup Database
set setup_database_name setup.onespin
if {$use_setup_database && [file isdirectory $setup_database_name]} {
    cd $script_path
    load_database -force $setup_database_name
} else {

###############
# Load Design #
# Use the SystemVerilog standard SV2012
cd $script_path
read_verilog -golden -version sv2012 {
    lubis_fifo.sv
}

cd $script_path


####################
# Elaborate Design #

#define black-box modules here

set_elaborate_option -golden -top lubis_fifo
elaborate            -golden


##################
# Compile Design #
set_compile_option   -golden -clock { {clk} }
set_compile_option   -golden -undriven_value input
compile              -golden


###############
# Final Setup #
set_clock_spec -period 2 clk

set_reset_sequence -golden { { rst=1 } }


##########################
# Configure Verification #
set_mode mv

# Save Setup Database
if {$use_setup_database} {
    cd $script_path
    save_database -force $setup_database_name
}

}

cd $script_path
read_sva  {
    fv_scoreboard.sv
}

cd $script_path


if {$auto_check && $auto_witness} {
    check -force -all [get_assertions]
} elseif {$auto_check} {
    check -force [get_assertions]
} elseif {$auto_witness} {
    check -force -pass [get_assertions]
}

if {$exit_after_execution} {
    exit -force
}
