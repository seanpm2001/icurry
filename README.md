icurry
======

ICurry is an intermediate format to compile Curry to different imperative
languages. ICurry is intended to be generic so that different target languages
can be supported with a similar effort.

The definition of ICurry is inspired by the Curry compiler
[Sprite](http://dx.doi.org/10.1007/978-3-319-63139-4_6)
which compiles Curry programs into LLVM code.
The definition of ICurry implemented in this package follows the
[paper on ICurry](http://arxiv.org/abs/1908.11101).

This package contains the definition of ICurry as
Curry data types (module `ICurry.Types`), a simple compiler
to translate Curry programs to ICurry, and an interpreter
for ICurry programs based on the small-step semantics of ICurry.
The latter can also be used to visualize the graph constructed
during the execution of ICurry programs.

These tools are available in the `icurry` binary installed
with this package.


Usage:
------

Note that the ICurry compiler is a prototype used to compile
single Curry modules into corresponding ICurry programs.
If a Curry module has several imports, one has to compile
these imports into ICurry manually (the automation of this
process will be done in the future).
In the following, we describe various uses of the `icurry` tool.

1. To compile a Curry program `Prog.curry` into the ICurry format,
   invoke the command

       > icurry Prog

   This will generate the file `.curry/Prog.icy`, i.e., the suffix `icy`
   is used for generated ICurry programs.

   In order to see a human-readable presentation of the generated program,
   use option `-v`, i.e.,
   
       > icurry -v Prog

2. One can also use a simple (i.e., not efficient) interpreter
   to execute ICurry programs and visualize their behavior.
   In this case, one has to provide the name of a 0-ary function `mymain`
   and invoke `icurry` by

       > icurry -m mymain Prog

    This compiles `Prog.curry` into ICurry (but do not store the
    compiled program in a file), invokes the ICurry interpreter
    (see `ICurry.Interpreter`), and shows the results of evaluating `mymain`.

    With option `--interactive`, the ICurry interpreter stops after
    each result and ask for a confirmation to proceed, which is useful
    if their might be infinitely many results.

    The ICurry interpreter can also visualize the term graph manipulated
    during execution as a PDF generated by `dot`. If `icurry` is invoked by

       > icurry -m mymain --graph Prog

    the graph after each step is shown by `evince` (see parameter `--viewer`)
    and each step is executed in one second.

    The option `--interactive` in combination with `--graph` shows more
    more details about the state of the interpreter and asks for
    a confirmation to proceed after each step of the interpreter:

       > icurry -m mymain --graph --interactive Prog

    More executions options are available by invoking the interpreter
    manually via the operation `ICurry.Interpreter.execProg`.


Some remarks about the ICurry interpreter:
------------------------------------------

The interpreter evaluates expressions up to head normal form.
In order to evaluate the main expression to normal form,
one can wrap it with the function `normalForm`, e.g.,

    mymain = normalForm (reverse [1,2,3])

The current version of the interpreter supports only the prelude
operations `normalForm` and `$!`.

----------------------------------------------------------------------------
