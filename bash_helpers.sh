#!/usr/bin/env bash

# Copyright Dave Taylor, 2017.

bash_script_dir="${BASH_SOURCE%/*}"

shopt -s expand_aliases

VERBOSE=false

function set_verbose()
{
	VERBOSE=$1
}

function atomic_copy()
{

	local src_path="$1"
	local dest_dir="$2"
	local tmp_file="/tmp/atomic_copy_file.$BASHPID"

	cp -p "$src_path" "$tmp_file"
	mv "$tmp_file" "$dest_dir"

}

function get_indentation()
{

	declare -i num_chars=$1
	declare -i i=0
	_indentation=""

	while [[ $i -lt $num_chars ]] ; do
		_indentation="$_indentation "
		i=$(( $i + 1 ))
	done

}

function verbose_log()
{
	if [[ $VERBOSE == true ]] ; then
		declare -i depth=$1
		shift
		get_indentation $(( $depth * 2 ))
		echo "${_indentation}$@" 1>&2
	fi
}

function echoerr()
{
	echo -e "$@" 1>&2
}

# This sends the output of a command into an array without creating a subshell

function cmd_to_array()
{

	one_line=false
	if [[ "$1" == "--one-line" ]] ; then
		one_line=true
		shift
	fi

	local whitespace=false
	if [[ "$1" == "-w" ]] ; then
		whitespace=true
		shift
	fi

	local array_name="$1"
	shift
	declare -a cmd=("$@")

	local output_dir="$bash_script_dir/.variables"
	local output_path="$output_dir/$array_name.$BASHPID"

	if [[ ! -d "$output_dir" ]] ; then
		mkdir -p "$output_dir"
	fi

	# This odd hack makes sure we capture the return value of the command
	local ret
	if eval "${cmd[@]}" > "$output_path" ; then
		ret=$?
	else
		ret=$?
	fi

	# Only read one line of the output, otherwise read the whole thing into an array
	if [[ $one_line == true ]] ; then
		local line
		read -r line < "$output_path"
		eval $array_name=\(\'$line\'\)
	else
		mapfile -t $array_name < "$output_path"
	fi

	if [[ $whitespace == true ]] ; then
		eval $array_name=\(\${$array_name[@]}\)
	fi

	rm -f "$output_path"

	return $ret

}

# This sends the first line of a command's output into a variable without creating a subshell

function cmd_to_var()
{

	local var_name="$1"
	shift
	declare -a cmd=("$@")

	local ret
	declare -a array

	if cmd_to_array --one-line array "${cmd[@]}" ; then
		ret=$?
	else
		ret=$?
	fi

	local var="${array[0]}"

	eval $var_name=\'$var\'

	return $ret

}

function strip_leading_zeroes()
{

	local string="$1"

	_value=$((10#$string))

}

function arg_is_set()
{

	local ret_val=-1

	# This is just like arg_index but adds one to the result,
	#   which is more commonly used in positional parameters
	#   instead of array indices

	if arg_index "$@" ; then
		ret_val=0
		_arg_position=$(($_arg_position+1))
		_next_arg_position=$(($_next_arg_position+1))
	fi

	return $ret_val

}

# Returns the index of a matching element and its next element
#   in _arg_position and _next_arg_position.
# Returns false if no match found

function arg_index()
{

	local arg
	local ret_val=-1
	local comparison="$1"
	shift

	# The returned position is in functional position, which starts w/ 1,
	#   not the same as array index position, which starts w/ 0.

	_arg_position=0

	for arg in "$@" ; do
		if [[ "$arg" == "$comparison" ]] ; then
			ret_val=0
			break
		fi
		_arg_position=$(($_arg_position+1))
	done

	_next_arg_position=$(($_arg_position+1))

	return $ret_val

}

function get_arg_count()
{

	declare -i count=0
	declare -i i=0
	while [[ $i -lt $# ]] ; do
		eval _arg="\$$i"
		if [[ "$_arg" != -* ]] ; then
			count=$(($count+1))
		fi
		i=$(($i+1))
	done

	_arg_count=$count

}

function get_arg()
{

	declare -i requested_arg=$1
	shift

	_arg="(no args)"

	declare -i arg_index=0
	declare -i i=1
	local found=false
	local possible_arg

	while [[ $i -le $# && $found == false ]] ; do

		eval possible_arg=\"\$$i\"
		if [[ "$possible_arg" != -* ]] ; then
			arg_index=$arg_index+1
		fi

		if [[ $arg_index == $requested_arg ]] ; then
			found=true
			_arg="$possible_arg"
		fi

		i=$i+1

	done

	test $found == true

}

function win_path()
{
	local cygwin_path
	cmd_to_var cygwin_path cygpath -waml "$1"
	echo "$cygwin_path"
}

function calculate_md5sum()
{

	declare -a md5sum_cmd=()
	local source="$1"

	if [[ "$OS" == Darwin ]] ; then
		md5sum_cmd+=(md5 -q)
		if [[ "$source" != "-" ]] ; then
			md5sum_cmd+=("$source")
		fi
	else
		md5sum_cmd+=(md5sum "$source")
	fi

	cmd_to_var _md5sum "${md5sum_cmd[@]}"

}

function get_stack_trace()
{


	declare -i i=${#FUNCNAME[@]}
	declare -i j=0

	_stack_trace=""

	if [[ $# -lt 1 || "$1" != "--quiet" ]] ; then
		_stack_trace="\nStack trace:"
	fi

	while [[ $i -gt 1 ]] ; do
		i=$i-1
		j=$j+1
		printf -v _stack_trace "%s\n%*s%s" "$_stack_trace" $j " " \
			"${FUNCNAME[$i]} (${BASH_SOURCE[$i]##*/}:${BASH_LINENO[$i]})"
	done

}

function start_process()
{

	local pid_path="$1"
	shift
	declare -a cmd_line=("$@")

	trap at_exit EXIT
	echo "$BASHPID" > "$pid_path"

	"${cmd_line[@]}"

}

function launch_process()
{

	local name="$1"
	shift
	declare -a cmd_line=("$@")

	local pid_path=/tmp/${BASH_SOURCE##*/}_${name}_pid.$BASHPID
	mkfifo "$pid_path"

	# setsid creates a new session group and thus new process group for
	#   this process and its children.  This repleases start_process()
	start_process "$pid_path" "${cmd_line[@]}" &

	eval read _${name}_pid < "$pid_path"

	rm -f "$pid_path"

}

function process_exists()
{
	local name="$1"
	eval if [[ -z \$\{_${name}_pid\+x} ]] \; then return -1 \; fi
	eval kill -0 \$_${name}_pid 2>/dev/null
}

function stop_process()
{

	local name="$1"

	eval local pid=\$_${name}_pid

	kill $pid > /dev/null 2>&1 || :

	# Subprocesses require 0.5 to die, so this should be enough time
	sleep 0.8

	kill -9 $pid > /dev/null 2>&1 || :

}

cmd_to_var OS uname -s

if [[ "$OS" == CYGWIN* ]] ; then
	function native_path() { win_path "$@"; }
	native_pty=winpty
elif [[ "$OS" == Darwin ]] ; then
	function native_path() { echo "$@"; }
	native_pty=""
elif [[ "$OS" == Linux ]] ; then
	function native_path() { echo "$@"; }
	native_pty=""
fi

# save_vars_to_file <save_file> <var1> [var2] ...
#   This will save all the named variables to the specified save file
#   If save file not specified, put under $bash_script_dir/.variables/function.

function save_vars_to_file()
{
	declare -i i=2
	mkdir_if_missing "$1"
	while [[ $i -le $# ]] ; do
		eval declare -p \${${i}}
		i=$(($i+1))
	done > "$1"
}

# load_vars <save_file>
#   This will load all the variables in the specified save file

alias load_vars_from_file=source

function save_vars()
{
	_target_path="$bash_script_dir/.variables/${FUNCNAME[1]}.$BASHPID"
	save_vars_to_file "$_target_path" $@
}

function load_vars()
{
	load_vars_from_file "$bash_script_dir/.variables/$1.$BASHPID"
}

function get_target_path()
{
	declare -i target_index=$1
	_target_path="${dependencies_targets[$target_index]}"
}

function get_source_paths()
{
	declare -i target_index=$1

	local source_index
	_source_paths=()
	for source_index in ${dependencies[$target_index]} ; do
		_source_paths+=(${dependencies_targets[$source_index]})
	done

}

function find_target_index()
{

	local test_target
	local target="$1"

	_target_index=0
	while [[ $_target_index -lt ${#dependencies_targets[@]} ]] ; do
		test_target="${dependencies_targets[$_target_index]}"
		if [[ "$test_target" == "$target" ]] ; then
			return 0
		fi
		_target_index=$(($_target_index+1))
	done

	return 1

}

function add_target_to_indices()
{

	_target_index=${#dependencies[@]}
	dependencies_targets[$_target_index]="$1"
	dependencies[$_target_index]=""
	dependencies_function_names[$_target_index]=""
	dependencies_function_wrappers[$_target_index]=""

}

function add_dependency_index()
{

	local dest_index=$1
	local src_index=$2

	dependencies[$dest_index]="${dependencies[$dest_index]} $src_index"

}

function copy_dependency_index()
{

	local src=$1
	local dest=$2

	dependencies[$dest]="${dependencies[$src]}"
	dependencies_targets[$dest]="${dependencies_targets[$src]}"
	dependencies_function_names[$dest]="${dependencies_function_names[$src]}"
	dependencies_function_wrappers[$dest]="${dependencies_function_wrappers[$src]}"

}

function dump_dependencies()
{
	local src=$1
	echo target=${dependencies_targets[$src]}
	echo deps=${dependencies[$src]}
	echo fn=${dependencies_function_names[$src]}
	echo wrapper=${dependencies_function_wrappers[$src]}
}

function visit_tree_leaves()
{

	declare -i top_node_index=$1
	declare -i depth=$2
	local visit_function_name="$3"

	shift 3

	if [[ "${dependencies[$top_node_index]}" == "" ]] ; then
		${visit_function_name/:/} $top_node_index $depth "$@"
	else
		for dep_index in ${dependencies[$top_node_index]} ; do
			visit_tree_leaves $dep_index $(($depth + 1)) "$visit_function_name" "$@"
		done
	fi

}

function update_target_if_newer()
{
	${@/:/}
}

function update_target_if_different()
{

	local function_name="$1"
	declare -i target_index=$2
	declare -i depth=$3

	local previous_target_md5="(none)"

	get_target_path $target_index
	local target_path="$_target_path"

	# Calculate the md5 of the previous target file

	if [[ -e "$_target_path" ]] ; then
		calculate_md5sum "$target_path"
		previous_target_md5="$_md5sum"
	fi

	if [[ "$function_name" != "" ]] ; then

		# Use slot zero as a temporary index to point to a temporary file
		#   that the generation function will put its output into

		copy_dependency_index $target_index 0
		local target_dir="${target_path%/*}"
		local target_filename="${target_path##*/}"
		local temp_target_path="$target_dir/.${target_filename}_temp.$BASHPID"
		dependencies_targets[0]="$temp_target_path"

		# If the function succeeds in generatin a file, then we check to see
		#   whether it's different than the original.  If not, we pretend
		#   the file has not been built

		if ${function_name/:/} 0 $depth ; then
			calculate_md5sum "$temp_target_path"
			local temp_target_md5="$_md5sum"
			if [[ "$temp_target_md5" != "$previous_target_md5" ]] ; then
				verbose_log $depth $previous_target_md5 is different
				mv "$temp_target_path" "$target_path"
				return 0
			fi
		fi

	fi

	# If we got here, then the generation function must have either failed or has
	#   generated an identical file to the previous target

	return 1

}

declare -a dependencies=("<src_index0> [src_index1] ...")
declare -a dependencies_targets=("<target_name>")
declare -a dependencies_function_names=("<function_name>")
declare -a dependencies_function_wrappers=("[function_wrapper_name]")

# $1 = destination target
# $2 [$3l [$4] ... = source targets
# Specfifies that the destination target depends on the specified source targets
# Returns the destination file for the dependency in _target_index

alias set_dependency=set_dependencies
function set_dependencies()
{

	local src_index dest dest_index function_wrapper index_args

	if [[ $# -lt 2 ]] ; then
		echoerr "set_dependencies(): Too few parameters: " $@
	fi

	index_args=false
	function_wrapper="update_target_if_newer"
	while [[ "$1" == --* ]] ; do
		case "$1" in
			--differen*)
				function_wrapper="update_target_if_different"
				;;
			--index*|--indic*)
				index_args=true
				;;
		esac
		shift
	done

	src_to_dest_function_name="$1"
	dest="$2"

	shift 2
	declare -a srcs=($@)

	if [[ $index_args == true ]] ; then
		dest_index=$dest
	else
		if ! find_target_index "$dest" ; then
			add_target_to_indices "$dest"
		fi
		dest_index=$_target_index
	fi

	dependencies_function_names[$dest_index]="$src_to_dest_function_name"
	dependencies_function_wrappers[$dest_index]="$function_wrapper"

	declare -i i=0
	while [[ $i -lt ${#srcs[@]} ]] ; do
		if [[ $index_args == true ]] ; then
			src_index=${srcs[$i]}
		else
			if ! find_target_index "${srcs[$i]}" ; then
				add_target_to_indices "${srcs[$i]}"
			fi
			src_index=$_target_index
		fi
		add_dependency_index $dest_index $src_index
		i=$(($i+1))
	done

	_target_index=$dest_index
	return 0

}

function touch_target()
{
	local target_index=$1
	get_target_path $target_index
	touch "$_target_path"
}

function test_target()
{

	local operation="$1"
	local target_index=$2

	get_target_path $target_index

	test $operation "$_target_path"

}

function is_target_newer_than()
{

	local target_path other_path

	declare -i target_index=$1
	declare -i other_index=$2

	get_target_path $target_index
	target_path="$_target_path"

	get_target_path $other_index
	other_path="$_target_path"

	test "$target_path" -nt "$other_path"

}

function create_variables_dir()
{
	local dir="$bash_script_dir/.variables"
	if [[ ! -e "$dir" ]] ; then
		mkdir -p "$dir"
	fi
}

function generate_target()
{

	local target="$1"
	if ! find_target_index "$target" ; then
		echoerr "Could not find dependencies index for $target"
	fi
	local target_index=$_target_index

	generate_index $target_index

}

function mkdir_if_missing()
{
	if [[ "$1" == */* ]] ; then
		local dir="${1%/*}"
		if [[ ! -e "$dir" ]] ; then
			mkdir -p "$dir"
		fi
	fi
}

function generate_index()
{

	create_variables_dir
	local comparison=$1
	if [[ $# -ge 2 ]] ; then
		comparison=$2
	fi
	generate_index_newer_than $comparison $1 0
}

function generate_index_newer_than()
{

	local comparison_index=$1
	local target_index=$2
	declare -i depth=$3
	local dirty=false

	local target_path="${dependencies_targets[$target_index]}"

	local deps="${dependencies[$target_index]}"

	declare -a target_deps_msg="target ${target_path##*/} depends on"

	if [[ ${#deps} -gt 0 ]] ; then
		local source_index
		for source_index in ${dependencies[$target_index]} ; do
			target_deps_msg+=(${dependencies_targets[$source_index]##*/})
		done
	else
		target_deps_msg+=("nothing!")
	fi

	verbose_log $depth "${target_deps_msg[@]}"

	if ! test_target -e $target_index ; then
		verbose_log $depth "${target_path##*/} doesn't exist"
		dirty=true
	elif [[ $comparison_index -eq -1 ]] ; then
		verbose_log $depth "forcing ${target_path##*/} dirty"
		dirty=true
	elif is_target_newer_than $target_index $comparison_index ; then
		local first="${target_path##*/}"
		local comparison_path="${dependencies_targets[$comparison_index]}"
		local second="${comparison_path##*/}"
		verbose_log $depth "$first newer than $second"
		dirty=true
	fi

	if [[ "$deps" != "" ]] ; then

		if [[ $comparison_index != -1 ]] ; then
			comparison_index=$target_index
		fi

		for source_index in $deps ; do
			generate_index_newer_than $comparison_index $source_index $(( $depth + 1 ))
			load_vars generate_index_newer_than
			if [[ $_dirty == true ]] ; then
				verbose_log $depth "forcing ${target_path##*/} dirty because ${dependencies_targets[$source_index]##*/} is dirty"
				dirty=true
			fi
		done

	fi

	# This executes the function to build the target and touches the target 
	#   afterwards (handy when the target is just a timestamp)
	#   This only happens though if the function and/or wrapper returned success
	#   If they fail, the file is untouched.

	local function_name="${dependencies_function_names[$target_index]}"
	local function_wrapper="${dependencies_function_wrappers[$target_index]}"
	if [[ "$function_name" != "" ]] ; then
	
		if [[ $dirty == true ]] ; then

			verbose_log $depth "${target_path##*/} dirty, running $function_wrapper $function_name ${target_path##*/}..."

			mkdir_if_missing "$target_path"
			if $function_wrapper "$function_name" $target_index $depth ; then
				touch "$target_path"
				verbose_log $depth "$function_name successfully built ${target_path##*/}"
			else
				verbose_log $depth "$function_name did not build new ${target_path##*/}"
			fi

		else

			verbose_log $depth "${target_path##*/} clean"

		fi

	fi

	_dirty=$dirty
	save_vars _dirty

	return 0

}

function start_profiling()
{
	PS4='(\T): '
	exec 3>&2 2> /tmp/profile.$BASHPID
	set -x
}

function stop_profiling()
{
	set +x
	exec 2>&3 3>&-
}

exit_traps=()

function add_exit_trap()
{
	exit_traps+=(${1/:/})
}

function remove_exit_trap()
{
	exit_traps=(${exit_traps[@]/$1})
}

function at_exit()
{
	for exit_trap in ${exit_traps[@]} ; do
		eval $exit_trap
	done
}

trap at_exit EXIT

function clean_temporary_variables()
{
	rm -f "$bash_script_dir"/.variables/*.$BASHPID \
		"$bash_script_dir"/.variables/*.$BASHPID
}

add_exit_trap clean_temporary_variables

BASH_HELPERS_LOADED=true

