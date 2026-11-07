; The module whose object llvm-strip of a host strips. llc of the host
; compiles it for ELF and for Mach-O, with the debug sections that its DWARF
; metadata gives. llvm-strip --strip-debug must remove those sections and
; leave the bytes of every allocated section as they were. It names no
; triple and no data layout, so llc takes both from -mtriple, and its file
; lies in the directory ".", so no object names a path of this machine.
@message = private unnamed_addr constant [14 x i8] c"Hello, world!\00"

declare i32 @puts(ptr)

define i32 @twice(i32 %n) !dbg !6 {
entry:
    #dbg_value(i32 %n, !10, !DIExpression(), !11)
  %sum = add i32 %n, %n, !dbg !12
  ret i32 %sum, !dbg !12
}

define i32 @main() !dbg !13 {
  %printed = call i32 @puts(ptr @message), !dbg !16
  %value = call i32 @twice(i32 21), !dbg !17
  %status = sub i32 %value, 42, !dbg !17
  ret i32 %status, !dbg !17
}

!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!3, !4}

!0 = distinct !DICompileUnit(language: DW_LANG_C11, file: !1, producer: "llvm-tools checks", isOptimized: false, runtimeVersion: 0, emissionKind: FullDebug, enums: !2)
!1 = !DIFile(filename: "debug.c", directory: ".")
!2 = !{}
!3 = !{i32 7, !"Dwarf Version", i32 4}
!4 = !{i32 2, !"Debug Info Version", i32 3}
!5 = !DIBasicType(name: "int", size: 32, encoding: DW_ATE_signed)
!6 = distinct !DISubprogram(name: "twice", scope: !1, file: !1, line: 3, type: !7, scopeLine: 3, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !9)
!7 = !DISubroutineType(types: !8)
!8 = !{!5, !5}
!9 = !{!10}
!10 = !DILocalVariable(name: "n", arg: 1, scope: !6, file: !1, line: 3, type: !5)
!11 = !DILocation(line: 3, column: 15, scope: !6)
!12 = !DILocation(line: 4, column: 14, scope: !6)
!13 = distinct !DISubprogram(name: "main", scope: !1, file: !1, line: 7, type: !14, scopeLine: 7, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !2)
!14 = !DISubroutineType(types: !15)
!15 = !{!5}
!16 = !DILocation(line: 8, column: 5, scope: !13)
!17 = !DILocation(line: 9, column: 12, scope: !13)
