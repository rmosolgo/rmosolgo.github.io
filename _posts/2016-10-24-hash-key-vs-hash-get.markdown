---
layout: post
title: "Hash#key? vs Hash#[]"
date: 2016-10-24 10:30
comments: true
categories:
- Ruby
---


I [read that](#) `Hash#key?` was slower than `Hash#[]` and it made me sad because, shouldn't `Hash#key?` generally require less work?

<!-- more -->

Besides that, there are cases where only `Hash#key?` will do the trick. For example, if you need to distinguish between these two cases:

- Hash key is not present
- Hash key is present, value is `nil`

then you _must_ use `Hash#key`.

## The Benchmark

So, I wrote a little benchmark:

```ruby
require "benchmark/ips"

tiny_hash = {1 => 1, 2 => 2, 3 => 3}
huge_hash = (1..10_000).reduce({}) { |m, i| m[i] = i; m }

Benchmark.ips do |x|
  x.report("tiny_hash.key? hit") { tiny_hash.key?(3) }
  x.report("huge_hash.key? hit") { huge_hash.key?(3) }
  x.report("tiny_hash.[]   hit") { tiny_hash[3] }
  x.report("huge_hash.[]   hit") { huge_hash[3] }
  x.compare!
end

puts "\n====================================\n"

Benchmark.ips do |x|
  x.report("tiny_hash.key? miss") { tiny_hash.key?(-1) }
  x.report("huge_hash.key? miss") { huge_hash.key?(-1) }
  x.report("tiny_hash.[]   miss") { tiny_hash[-1] }
  x.report("huge_hash.[]   miss") { huge_hash[-1] }
  x.compare!
end
```

And here was my result

```sh
$ ruby -v
ruby 2.3.1p112 (2016-04-26 revision 54768) [x86_64-darwin14]
$ ruby hash_bench.rb
Warming up --------------------------------------
  tiny_hash.key? hit   252.873k i/100ms
  huge_hash.key? hit   245.380k i/100ms
  tiny_hash.[]   hit   280.718k i/100ms
  huge_hash.[]   hit   284.686k i/100ms
Calculating -------------------------------------
  tiny_hash.key? hit      8.538M (± 5.9%) i/s -     42.736M in   5.024150s
  huge_hash.key? hit      8.506M (± 5.4%) i/s -     42.451M in   5.006062s
  tiny_hash.[]   hit      9.240M (± 7.5%) i/s -     46.038M in   5.014504s
  huge_hash.[]   hit      9.743M (± 4.9%) i/s -     48.681M in   5.008925s

Comparison:
  huge_hash.[]   hit:  9743415.0 i/s
  tiny_hash.[]   hit:  9240225.3 i/s - same-ish: difference falls within error
  tiny_hash.key? hit:  8537718.1 i/s - 1.14x  slower
  huge_hash.key? hit:  8506284.7 i/s - 1.15x  slower


====================================

Warming up --------------------------------------
  tiny_hash.key? miss   281.127k i/100ms
  huge_hash.key? miss   265.594k i/100ms
  tiny_hash.[]   miss   270.277k i/100ms
  huge_hash.[]   miss   265.036k i/100ms
Calculating -------------------------------------
  tiny_hash.key? miss      8.798M (± 4.1%) i/s -     44.137M in   5.025380s
  huge_hash.key? miss      7.597M (± 7.7%) i/s -     37.714M in   5.004217s
  tiny_hash.[]   miss      8.323M (± 6.7%) i/s -     41.623M in   5.027045s
  huge_hash.[]   miss      7.824M (± 5.5%) i/s -     39.225M in   5.029239s

Comparison:
  tiny_hash.key? miss:  8798106.0 i/s
  tiny_hash.[]   miss:  8322700.3 i/s - same-ish: difference falls within error
  huge_hash.[]   miss:  7824137.4 i/s - 1.12x  slower
  huge_hash.key? miss:  7597444.9 i/s - 1.16x  slower
```

What's up with that?!

## Why??

Let's compare the implementation of these methods:

- [`Hash#[]`](https://ruby-doc.org/core-2.3.1/Hash.html#method-i-5B-5D):

```c
VALUE
rb_hash_aref(VALUE hash, VALUE key)
{
    st_data_t val;

    if (!RHASH(hash)->ntbl || !st_lookup(RHASH(hash)->ntbl, key, &val)) {
        return rb_hash_default_value(hash, key);
    }
    return (VALUE)val;
}
```

- [`Hash#key?`](https://ruby-doc.org/core-2.3.1/Hash.html#method-i-key-3F)


```c
VALUE
rb_hash_has_key(VALUE hash, VALUE key)
{
    if (!RHASH(hash)->ntbl)
        return Qfalse;
    if (st_lookup(RHASH(hash)->ntbl, key, 0)) {
        return Qtrue;
    }
    return Qfalse;
}  
```

They're remarkably similar. They _both_:

- Check that `self` has an `ntbl`
- Lookup the value for `key` in `ntbl`

But, `Hash#key?` does something a bit unusual: to doesn't capture the
value of `key` in `self`. Instead, it uses the return value of `st_lookup`
to detect whether the lookup was a hit or a miss. In the case of a hit, it returns `Qtrue` (The C name for Ruby's `true`.)

## Digging deeper: `st_lookup`

`st.c` provides a general purpose hash table implementation. It is widely used by Ruby. `st_lookup` looks up a key in a table. On a hit, it writes the value to a pointer and returns `1`. On a miss, it returns `0`.

`st_lookup` accepts `0` as input for the value pointer. And in that case, it does nothing with value. For example, here's a snippet from the hit case:

```c
if (value != 0) *value = ptr->record;
return 1;
```

Referring back to `Hash#[]` and `Hash#key?`, that's the most notable distinction:

- `Hash#[]` sends a `st_data_t*` to `st_lookup`
- `Hash#key?` sends `0` to `st_lookup`

But ... why would it be slower to use `0`? 😿

## VM Optimization

I was going to report my failure to the twitter thread where I first saw this, but I noticed a new [response from @schneems](https://twitter.com/schneems/status/790299300328726528):

> "It's optimized by the interpreter to skip the usually more expensive method lookup"

Ok, let's check that! We can see the Ruby bytecode by using the `RubyVM` module.

Let's compare the output of `a[:a]` and `a.key?(:a)`:

```ruby
# a[:a] to Ruby bytecode
puts RubyVM::InstructionSequence.compile("a[:a]").disasm
# == disasm: <RubyVM::InstructionSequence:<compiled>@<compiled>>==========
# 0000 trace            1                                               (   1)
# 0002 putself
# 0003 opt_send_without_block <callinfo!mid:a, argc:0, FCALL|VCALL|ARGS_SIMPLE>
# 0005 putobject        :a
# 0007 opt_aref         <callinfo!mid:[], argc:1, ARGS_SIMPLE>
# 0009 leave

# a.key?(:a) to Ruby bytecode
puts RubyVM::InstructionSequence.compile("a.key?(:a)").disasm
# == disasm: <RubyVM::InstructionSequence:<compiled>@<compiled>>==========
# 0000 trace            1                                               (   1)
# 0002 putself
# 0003 opt_send_without_block <callinfo!mid:a, argc:0, FCALL|VCALL|ARGS_SIMPLE>
# 0005 putobject        :a
# 0007 opt_send_without_block <callinfo!mid:key?, argc:1, ARGS_SIMPLE>
# 0009 leave
```

Did you see the difference?

- `a[...]` was compiled to `opt_aref` (an optimized call)
- `a.key?(...)` was compiled to `opt_send_without_block` (a normal method call)


Here's the definition for `opt_aref`:

```c
/**
  @c optimize
  @e []
  @j 最適化された recv[obj]。
 */
DEFINE_INSN
opt_aref
(CALL_INFO ci, CALL_CACHE cc)
(VALUE recv, VALUE obj)
(VALUE val)
{
  if (!SPECIAL_CONST_P(recv)) {
  	if (RBASIC_CLASS(recv) == rb_cArray && BASIC_OP_UNREDEFINED_P(BOP_AREF, ARRAY_REDEFINED_OP_FLAG) && FIXNUM_P(obj)) {
  	  val = rb_ary_entry(recv, FIX2LONG(obj));
  	}
    else if (RBASIC_CLASS(recv) == rb_cHash && BASIC_OP_UNREDEFINED_P(BOP_AREF, HASH_REDEFINED_OP_FLAG)) {
      val = rb_hash_aref(recv, obj);
    }
    else {
      goto INSN_LABEL(normal_dispatch);
    }
  } else {
    INSN_LABEL(normal_dispatch):
    PUSH(recv);
    PUSH(obj);
    CALL_SIMPLE_METHOD(recv);
  }
}
```


The earlier cases check if the receiver is an Array or Hash, and that the method hasn't been redefined. In that case, it directly calls the C function for lookup. If any of those checks fail, it uses `normal_dispatch` to execute the instruction. `Hash#key?`, on the other hand, _always_ uses a full method lookup.

Here's `opt_send_without_block`:

```c
/**
  @c optimize
  @e Invoke method without block
  @j Invoke method without block
 */
DEFINE_INSN
opt_send_without_block
(CALL_INFO ci, CALL_CACHE cc)
(...)
(VALUE val) // inc += -ci->orig_argc;
{
    struct rb_calling_info calling;
    calling.block_handler = VM_BLOCK_HANDLER_NONE;
    vm_search_method(ci, cc, calling.recv = TOPN(calling.argc = ci->orig_argc));
    CALL_METHOD(&calling, ci, cc);
}
```

You can see `vm_search_method`, where the method is looked up.

## Conclusion

`Hash#[]` gets an optimized VM instruction, so it runs faster than `Hash#key?`. But sometimes _only_ `Hash#key?` will do the trick!
