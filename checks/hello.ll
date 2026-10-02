; The module that the recipe runs through opt and llc of a host, for each
; of the six triples that antic compiles for. It names no triple and no data
; layout, so llc takes both from -mtriple. At -O2, opt inlines @sum into
; @main and folds the loop.
@message = private unnamed_addr constant [14 x i8] c"Hello, world!\00"

declare i32 @puts(ptr)

define internal i32 @sum(i32 %n) {
entry:
  br label %loop

loop:
  %i = phi i32 [ 0, %entry ], [ %next, %loop ]
  %total = phi i32 [ 0, %entry ], [ %add, %loop ]
  %add = add i32 %total, %i
  %next = add i32 %i, 1
  %done = icmp eq i32 %next, %n
  br i1 %done, label %exit, label %loop

exit:
  ret i32 %add
}

define i32 @main() {
  %printed = call i32 @puts(ptr @message)
  %sum = call i32 @sum(i32 10)
  %status = sub i32 %sum, 45
  ret i32 %status
}
