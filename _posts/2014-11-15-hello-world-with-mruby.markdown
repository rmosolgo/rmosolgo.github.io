---
layout: post
title: "\"Hello World\" with mruby"
date: 2014-11-15 19:38
categories:
  - mruby
  - Ruby
---

[mruby](http://www.mruby.com) is an implementation of Ruby that's designed to be lightweight & integrated with C. To get started, you can run a bit of Ruby code from _inside_ C code.

<!-- more -->

"Hello World" with mruby looks like this:

- Set up a new project and include mruby as a submodule
- Write some C code that loads mruby and executes some Ruby code
- Compile the C code & run the resulting binary

You can find an example similar to this one [on GitHub](https://github.com/rmosolgo/mruby-examples/tree/master/01_hello_world).

## Start a project

Make a directory for your new project and enter it:

```
$ mkdir ~/hello-mruby
$ cd ~/hello-mruby
```

Clone mruby source and compile mruby:

```
$ git clone git@github.com:mruby/mruby.git
$ cd mruby
$ make
$ cd ..
```

(You need bison and Ruby to compile mruby, see the [install guide](https://github.com/mruby/mruby/blob/master/INSTALL) for more information.)

You can check if compilation was successful by running `mirb` (interactive mruby):

```
$ mruby/bin/mirb
mirb - Embeddable Interactive Ruby Shell

> 1 + 1
 => 2
```

## Write the program

Here's the whole of `hello_world.c`:

```c
/* include mruby VM & compiler */
#include "mruby.h"
#include "mruby/compile.h"

int main(void)
{
  /* make a mruby instance */
  mrb_state *mrb = mrb_open();

  /* write some code */
  char code[] = "p 'Hello world!'";

  /* use mruby to execute code from string */
  mrb_load_string(mrb, code);

  return 0;
}
```

Let's break that down:

- __Include mruby & compiler__. The mruby VM takes bytecode instructions. The compiler is used to turn a string of Ruby code into mruby bytecode. `mrb_load_string` handles both steps: Parse & compile Ruby code, then execute with the mruby VM.

- __Make a mruby instance__. Create an instance of the mruby VM. This object contains the state of the Ruby evnironment. Besides using it to execute code, you can inject values into the Ruby environment or call Ruby code from C.

- __Use mruby to execute code from string__. As described above, in this case, the string will be turned into VM instructions first, then executed by mruby.

## Compile & run

Compile your C application, referencing the necessary mruby files:

```
$ gcc hello_world.c -o hello_world -Imruby/include  -lmruby  -Lmruby/build/host/lib
```

Then, execute the resulting binary:

```
$ ./hello_world
"Hello world!"
```

You did it!

## What next?

- Use `mrbc` to precompile `.rb` into mruby bytecode.
- Modify `mrb_state` from C with things like `mrb_define_class`, `mrb_define_method` and `mrb_define_const`.
- Call Ruby methods from C with `mrb_funcall`.

However, I don't know of any English documentation for these things yet!
