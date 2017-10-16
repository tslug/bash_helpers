#!/bin/bash

set -e
set -u

script_dir="${BASH_SOURCE%/*}"

if [[ -z ${BASH_HELPERS_LOADED+x} && -f "$script_dir/bash_helpers/bash_helpers.sh" ]] ; then
        source "$script_dir/bash_helpers/bash_helpers.sh"
fi

function make_output()
{
	get_target_path $1
	get_source_paths $1
	declare -i depth=$2

	verbose_log $depth Calculating checksum and converting input file ${_source_paths[0]##*/} to ${_target_path##*/}...
	calculate_md5sum "${_source_paths[0]}"
	echo "$_md5sum: " | cat - "${_source_paths[0]}" | sed -s s/cat/dog/g > "$_target_path"
}

function make_input()
{
	get_target_path $1
	declare -i depth=$2
	verbose_log $depth Saving output to ${_target_path##*/}
	echo "There is no greater companion than the cat." > "$_target_path"
}

function usage()
{
	echo "$0 [ --verbose ] [ --rebuild-all] < simple | order >"
}

function set_up_simple_test()
{
	set_dependencies make_input: /tmp/test_input.txt "${BASH_SOURCE}"
	set_dependencies make_output: /tmp/test_output.txt /tmp/test_input.txt
}

function create_file()
{

	get_target_path $1
	get_source_paths $1

	declare -i depth=$2
	declare -i total=0
	declare -i i=0
	declare -i num

	while [[ $i -lt ${#_source_paths[@]} ]] ; do
		read num < "${_source_paths[$i]}"
		total=$(($total + $num))
		i=$(($i+1))
	done

	echo $(( $total * ( $depth + 1 ) )) > "$_target_path"

}

function create_node_and_children()
{

	declare -i depth=$1
	declare -i max_depth=$2
	local top_dir="$3"
	declare -i max_children=$4

	filename="$top_dir/node${#target_indicies[@]}_d$depth"
	add_target_to_indicies "$filename"
	local target_index=$_target_index
	target_indexes+=$_target_index

	declare -i num_children=0
	if [[ $depth -lt $max_depth ]] ; then
		num_children=$(($RANDOM % $max_children))
	fi

	if [[ $num_children -gt 0 ]] ; then

		declare -a children_indicies=()

		while [[ $child -lt $num_children ]] ; do
			create_node_and_children $(($depth+1)) $max_depth "$top_dir" $max_children
			children_indicies+=$_target_index
			child=$(($child+1))
		done

		set_dependencies --indicies create_file: $target_index ${children_indicies[@]}

	fi

	_target_index=$target_index

}

function create_leaf
{
	get_target_path $1
	declare -i depth=$2
	echo $(( ($RANDOM % 40) / ($depth + 1) )) > "$_target_path"
}

function create_dependency_tree()
{

	load_vars_from_file "$1"

	RANDOM=$random_seed

	create_node_and_children 0 $max_depth "$top_dir" "$max_children"
	declare -i final_output_index=$_target_index

	_target_index=$final_output_index

}

function update_file()
{
	get_target_path $1
	get_source_paths $1
	cp "${_source_paths[0]}" "$_target_path"
}

function new_args()
{

	get_target_path $1
	get_source_paths $1

	cp "${_source_paths[0]}" "$_target_path"
	create_dependency_tree "$_target_path"

}

if arg_is_set --help "$@" ; then
	usage
	exit 1
fi

if arg_is_set --verbose "$@" ; then
	set_verbose true
fi

rebuild_all=false
if arg_is_set --rebuild-all "$@" ; then
	rebuild_all=true
fi

declare -i test_output_target_index=-1

if get_arg 1 "$@" ; then

	top_dir="/tmp/test_bash_helpers"

	if [[ "$_arg" == "simple" ]] ; then

		simple_test_dir="$top_dir/simple"
		set_up_simple_test  "$simple_test_dir"
		set_dependencies make_input: "$simple_test_dir/input.txt" "${BASH_SOURCE}"
		set_dependencies make_output: "$simple_test_dir/output.txt" "$simple_test_dir/input.txt"
		test_output_target_index=$_target_index

	elif [[ "$_arg" == "order" ]] ; then

		# These are the primary input parameters that drive
		#   the output of the test, but for any given set, the
		#   output should always be the same unless it's a parallel
		#   run
		declare -i random_seed=0
		declare -i max_depth=5
		declare -i max_children=5
		order_top_dir="$top_dir/order"
		order_test_dir="$order_top_dir/order-md${max_depth}-mc${max_children}-r${random_seed}"

		cmd_args_path="$order_top_dir/cmd_args"
		last_successful_cmd_args_path="$order_top_dir/last_successful_cmd_args"

		# Command line args from last run overrides defaults
		if [[ -f "$cmd_args_path" ]] ; then
			load_vars_from_file "$cmd_args_path"
		fi

		get_arg_count "$@"
		if [[ $_arg_count -gt 1 ]] ; then
			get_arg 2 "$@"
			random_seed=$_arg
			if [[ $_arg_count -gt 2 ]] ; then
				get_arg 3 "$@"
				max_depth=$_arg
				if [[ $_arg_count -gt 3 ]] ; then
					get_arg 4 "$@"
					max_children=$_arg
				fi
			fi
		fi

		tree_args_path="$order_test_dir/tree_args"

		# Save off the parameters we want as the command line args
		save_vars_to_file "$cmd_args_path" random_seed max_depth max_children

		# The random seed file is depenedent on the command line arguments changing
		#   We actually have to generate this file before specifying the rest of the
		#   dependencies, because those dependencies depend on the output

		set_dependencies --difference new_args: "$tree_args_path" "$cmd_args_path"
		tree_args_index=$_target_index

		declare -i comparison_index=$tree_args_index
		if [[ $rebuild_all == true ]]  ; then
			comparison_index=-1
		fi

		generate_index $tree_args_index $comparison_index

		# We now set the random number seed, which will change how the tree is built

		set -x

		create_dependency_tree "$tree_args_path"
		test_output_target_index=$_target_index

		set_dependencies create_dependency_tree: 

	else
		usage
		exit 1
	fi

else

	usage
	exit 1

fi

declare -i comparison_index=$test_output_target_index
if [[ $rebuild_all == true ]]  ; then
	comparison_index=-1
fi

generate_index $test_output_target_index $comparison_index

get_target_path $test_output_target_index
cat "$_target_path"

TEST_BASH_HELPERS_LOADED=true
