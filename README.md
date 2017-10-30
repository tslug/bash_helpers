# Bash Helpers

Bash Helpers is a source-able bash script that allows you to specify file
dependencies and how to turn a file from its dependencies into its
final form.

It is mostly implemented in one process and depends on no other packages
besides bash.  This is specifically to better support embedded systems
that are tight on space, to support Cygwin which pays a large performance
penalty for spawning subprocesses, and to create more efficient, less
bug-prone scripts that do not require anything but bash.

## What Is Bash Helpers Like?

Bash Helpers can be thought of as an implementation of make using only
bash internals.

It can also be thought of as a functional language implemented on top
of bash in order to help you avoid the most common bugs you see in
bash scripts, like caching issues, stale files, inconsistent state,
and having to regenerate previous work.

## Why?

I wrote 7k lines of regular bash script for a devops contract and
realized this would have saved me most of my debugging time, which
was mostly regarding dependencies I missed, caches with stale or
unupdated files, etc.

Could argue that using make would have reduced those bugs, but make's
build rules are fairly rudimentary compared to the full power of a
bash function.

I prefer the tight integration with bash and lack of dependency on any
other packages.

## Getting Started

While it's perhaps the most-installed software on the planet, bash is still
unfortunately an imperative scripting language.

Let's make some lemonade with those lemons.  In a new bash shell, type the
following:

```
source bash_helpers.sh

function make_lemonade()
{
	cat ingredient* > lemonade
}

echo lemon > ingredient1
echo lemon > ingredient2
echo lemon > ingredient3

set_dependencies make_lemonade: lemonade ingredient*
lemonade_index=$_target_index

generate_index $lemonade_index

cat lemonade
```

This says that the file lemonade depends on all the files in the current
directory that start with the name "ingredient".  Because the lemonade
file doesn't exist, it will generate lemonade from the ingredient files
by calling the make_lemonade function, which concatinates the ingredient
files into the lemonade file.

Unfortunately, this first attempt at lemonade is too bitter.

Let's swap out two of the three lemons with sugar and water:

```
echo sugar > ingredient2
echo water > ingredient3
```

Now let's make the lemonade again, this time asking bash_helpers to be verbose so that we can see
what it's doing to make the lemonade the second time through.

```
set_verbose true
generate_index $lemonade_index
```

Notice that we didn't have to specify the dependencies again.  If you
read the output of generate_index, you will notice that it saw that
ingredient1 file didn't get newer than the lemonade file, but it had
to make new lemonade because the ingredient2 and ingredient3 files were
newer than the lemonade file, and lemonade depends on all three ingredient
files.

Now that we've nailed lemonade, let's generalize the solution to work
with any fruit:

```
function pick_fruit()
{

	local fruit_type=lemon

	if [[ -f fruit_type ]] ; then
		read fruit_type < fruit_type
	fi

	echo $fruit_type > ingredient1

}

set_dependencies --different pick_fruit: ingredient1 fruit_type

generate_index $lemonade_index
```

This looks for a fruit_type file, and because it doesn't see one, it makes
the fruit_type lemon.  However, because we specified the "--different"
flag in set_dependencies, and because "lemon" is no different than
what was in the ingredient1 file before, when we generate the lemonade
file again, we can see the ingredient1 file hasn't changed, even though
it's newer, so it keeps the old lemonade file we had before and doesn't
regenerate it.

Enough lemonade.  Time to shut up and make apple juice:

```
set_verbose false
echo apple > fruit_type
generate_index $lemonade_index
```

Because ingredient1 now depends on the fruit_type file, and the fruit_type
has changed to apple, the new ingredient1 file will have an apple in it,
which is substantively different than a lemon, so now we've got apple
juice in our lemonade file.

As an encore, apple juice, loudly and from the beginning:

```
set_verbose true
generate_index $lemonade_index -1
```

Passing a second index to generate_index will specify the file index of a comparison
file you want to compare the target and its dependencies against for changes in modification time.
Anything newer than the comparison file will trigger rebuilding.

When you pass the comparison index -1, it forces all targets to be remade from scratch.

## Preqrequisites / Tested Environments

Bash Helpers requires Bash 3 or later.

If using the --different parameter on set_dependencies, it also requires
md5sum utility, which is pre-installed on OSX, Cygwin, and the vast majority
of Linux distributions.  The md5sum utility can be found in the coreutils
package on the handful that do not install it by default.

Bash Helpers has been tested on OSX Yosemite with Bash 3 and on Cygwin
with Bash 4 under Windows 10 Pro.  The linux utility example requires
Docker be installed and running, and it has been tested on the same systems.

## Installing

You can get Bash Helpers from:

```
git clone git://github.com/tslug/bash_helpers.git
```

To load up bash_helpers.sh, include this in your script:

```
source bash_helpers.sh
```

## Function Reference / API

### set_dependencies [--indices] [--different] "<dependency_function>: [arguments] ..." <target_file | target_index> <dependency_file | dependency_index> [dependency_file | dependency_index] ...

This states that the target file (or target file index if --indices is
passed) depends on the specified dependency files (or dependency file
indices if --indices is passed).

If any of the dependency files are newer than the target file, the
specified dependency_function will be called in order to generate the
target file.  When it is called, it will be passed the index of the
target in the first argument, followed by the current dependency tree
depth (integer), followed by any arguments optionally passed.

For small numbers of dependencies, using --indices will not improve
performance.  However, after a dozen or more files, using --indices is
considerably faster, as it executes in constant time instead of taking
time proportional to the number of files that have been mentioned in
set_dependencies before.

The --different parameter will force the generation of the target every
time into a dummy file, and then it will compare what was generated in
that dummy file with what currently exists in the target file.  If they're
identical, the target file will not be replaced.  This makes it so that
the target file's modification time will not change if the contents are
the same as before.  Using this option is expensive and should be used
sparingly.

Dependencies are internally wired together to create a potentially complex
dependency tree.

This will replace any pre-existing dependencies for that target.

Returns the target index as an integer variable in $\_target\_index

### get_target_path <target_index>

This will return into the variable $\_target\_path the target path
for the specified target index.  It is for use in functions passed by
set_dependencies.

### get_source_paths <target_index>

This will return into the array $\{\_source\_paths\[@\]\} the paths for
all the dependency files that the target index depends on.  It is for
use in functions passed by set_dependencies.

### add_target_to_indices <target_path>

This adds the target path to the dependencies and returns a target
index.  This is helpful when building a complex dependency tree
efficiently, so that you can use set_dependencies --indices for
more performance.

This still requires set_dependencies to be run on the target index
to set up a full dependency.

### add_dependency_index <target_index> <dependency_index>

This adds a new dependency to a pre-existing dependency created with
set_dependencies.  This is helpful when you want to change your
dependencies efficiently.

### dump_dependenciesa <target_index>

This dumps all dependency information stored about the target index.

### visit_tree_leaves <top_node_index> <depth> <visit_function_name: [args] ...>

Starting at the target index specified as the top_node_index, this will
traverse the dependency tree calling the visit function with the top node
index, followed by the current depth of the visited node, followed by
any args specified.

This is helpful for adding dependencies to a dependency tree.  See the
./test_bash_helpers.sh order command for an example where it adds
dependencies to the tree leaves.

### find_target_index <target_path>

This will return into the variable $\_target\_index the index associated
with the target path.

If no target index is found, it will return 1 (false), otherwise 0 (true).

### declare -a dependencies=("<src_index0> [src_index1] ...")

This is is the array that stores all the dependency indexes for a target
in a space-separated string.

### declare -a dependencies_targets=("<target_name>")

This is is the array that stores all the target pathnames for each
target index.

### declare -a dependencies_function_names=("<function_name>")

This is the array that stores all the functions used to generate the
target pathnames for each target index.

### declare -a dependencies_function_wrappers=("[function_wrapper_name]")

This is is a wrapper used to call the dependency function that generates
a target, currently used to implement the --different feature of
set_dependencies.

### generate_index <target_index> [comparison_index]

This satisfies all the dependencies (see set_dependencies) for the target
recursively in a depth-first traversal of the dependency tree.

If the optional comparison index is used, all files in the dependency
tree will be compared against that file's modification time.  If the
comparison index is set to -1, all targets will be regenerated from
scratch using the set_dependencies functions submitted earlier.

### generate_target <target_path>

This looks up the target index for the specified target path and
then calls generate_index with it.  It's considerably slower than
generate_index.

### set_verbose <true | false>

This makes the generate_index function print to stderr status messages
about the dependencies as they're satified.

### verbose_log <depth> <log message> ...

If set_verbose is set to true, then calling verbose_log will print out the
specified message to stderr.

The depth parameter is an integer indicating how deep into the dependency
tree the 

### echoerr [-n] <log message> ...

This will print the log message to stderr.

The -n parameter will prevent a newline from being printed.

### arg_is_set <number> <arguments> ...

This will return 0 (true) if the argument number is set in arguments.  In calculating
this, it skips any arguments that start with the character -.  So if \$@=

```
./lemonade_maker.sh hi --verbose there
```

arg_is_set 1 and arg_is_set 2 will return true, but arg_is_set 3 will be false.

### get_arg_count <arguments> ...

This counts the number of arguments passed.

Like arg_is_set, this will skip any elements that start with -.

### get_arg <argument_number> <arguments> ...

This returns the specified argument in the variable \$\_arg.  Like arg_is_set and
get_arg_count, it skips any arguments that start with -.

### native_path <path>

This takes a pathname and puts it on stdout using the native path format,
which is the same on everything, except for Cygwin, which will put it in
the drive letter format Windows native programs tend to prefer.

### calculate_md5sum <path>

This calculates the md5sum of the file at path and puts the result in
the variable \$\_md5sum.

### save_vars_to_file <path> <variable_name_1> [variable_name_2] ...

This saves all the specified variable names to the specified path.

### load_vars_from_file <path>

This loads all variables stored in the specified path as locals.

### save_vars <variable_name1> [variable_name2] ...

Same as save_vars_to_file, but it stores variables to the .variables directory
in the script location using a temporary generated filename specific to the process number.

### load_vars

This loads all variables stored by save_vars in the same process.

### add_exit_trap <function_name:>

This adds the specified function to the sequence of functions called when the
bash shell is exiting.  A trap is added by default to clean all temporary
variables associated with the process in the .variables directory.

### BASH_HELPERS_LOADED=true

The BASH_HELPERS_LOADED variable is set to "true" after the bash_helpers.sh
file has been sourced.  This can be helpful in preventing recursive inclusion
of the bash_helpers.sh file.

## Limitations

You must put only one script using bash_helpers in a given directory.
This sounds ridiculous, and it is, but it also encourages you to make
different scripts simply different targets and dependencies in one script.
This is one of the key advantages of functional programming.

You cannot run set_dependencies or generate_index in the background
or subprocesses.  They all need to run in the same process together.

Bash Helpers is not currently able to be run in parallel, but it
is designed to support this in the future.  Because most projects
featuring parallel builds really only need them to be parallel for
certain compute-intensive stages, the general workaround is to run
these stages explicitly in parallel inside of a given set_dependencies
function, and then you wait for the processes to end before returning
from that function.

## Side Effects

Bash Helpers will create two subdirectories in the same directory of any
script calling it, one called .variables, another called .timestamps.

The .variables directory is used to store variables saved with the
save_vars command.

The .timestamps directory is a convenience directory that allows you to
create empty files whose modification times act as timestamps.  This is
handy when your target represents a goal that depends on certain files
getting generated, rather than an actual output file with contents you
want to read.

## Stability Tips & Future Proofing Tips

Functional programming takes some getting used to.  Some tips to stay safe:

* Only generate the target file in your set_dependencies function.  Change no other files or you will hate yourself later.
* Do not set global variables in your set_depenendencies function.  Same thing, later date self-hatred prevention.
* You have to think harder about your problem, but once written, you also tend to get fewer bugs.
* Do not assume dependencies will be satisfied in the order presented.

Writing your code this way will also prepare your code for parallel
generation support, which will come for free free if you are rigorous
about preventing side-effects in your set_dependencies function.

Maintaining these disciplines will also dramatically reduce your bugs in
regular single-threaded code.

While not required, ending set_dependencies functions with a : improves
readability.  The trailing colon will be stripped from the function name
when executed.

## Memory Use Characteristics

Bash Helpers should not leak memory, but it does create a few arrays that scale in
size linearly with the number of dependencies that are set.  The payload of these
entries is a few bytes per dependency file, the target pathname, the generation
function name, and less than 30 bytes for the rest.

Using the --difference option will spawn an md5sum (md5 on OSX) subprocess.  No
other options will create a new process.

## Performance Tips

Bash Helpers has been designed to rely on bash internals and to avoid
forking new processes, in order to maximize speed on embedded systems,
and Cygwin, which does not support copy-on-write forks.

In general, you want to set as many dependencies as you can up front,
so that you only have to execute generate_index once, and it does all
the work of delivering all your targets.

Setting dependencies with --different will make the dependencies
comparatively expensive to evaluate, as it always generates the target
in a dummy file and then compares the md5sum of that file to the
md5sum of the existing target file.  So this also spawns two md5sum
processes.  It should be used sparingly.

Every time you call set_dependencies, it returns the index of the target
file in the \_target\_index variable.  If you save these indexes into
local variables, you can use them later in lieu of filenames
when creating new dependencies by using the --indices parameter.  This
makes the set_dependencies command a lot faster, as it doesn't have to
search through all its pathnames to see which index to use.

Whether using --indices in set_dependencies or not, internally, all
dependencies are stored as indexes, so the generate_index speed will be
the same for both.

## Can generate_index run in parallel?

The generate_index call is currently single-threaded.

While designed to allow today's code to be executed in parallel someday,
I haven't implemented it yet because it adds considerable complexity to
the code, it will slow down single-threaded performance somewhat with
that increased complexity.

## Why did you use global variables like $_target_index or ${_sources_list[@]}?

In order to avoid creating subshells and to avoid using stdin/stdout
which might be of use to the programmer, I decided to return information
in globals.

