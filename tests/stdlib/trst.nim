discard """
  output: '''

[Suite] RST parsing

[Suite] RST tables

[Suite] RST indentation

[Suite] Warnings

[Suite] RST include directive

[Suite] RST escaping

[Suite] RST inline markup
'''
"""

# tests for rst module

import ../../lib/packages/docutils/[rstgen, rst, rstast]
import unittest, strutils
import std/private/miscdollars
import os

const preferMarkdown = {roPreferMarkdown, roSupportMarkdown, roNimFile, roSandboxDisabled}
const preferRst = {roSupportMarkdown, roNimFile, roSandboxDisabled}

proc toAst(input: string,
            rstOptions: RstParseOptions = preferMarkdown,
            error: ref string = nil,
            warnings: ref seq[string] = nil): string =
  ## If `error` is nil then no errors should be generated.
  ## The same goes for `warnings`.
  proc testMsgHandler(filename: string, line, col: int, msgkind: MsgKind,
                      arg: string) =
    let mc = msgkind.whichMsgClass
    let a = $msgkind % arg
    var message: string
    toLocation(message, filename, line, col + ColRstOffset)
    message.add " $1: $2" % [$mc, a]
    if mc == mcError:
      if error == nil:
        raise newException(EParseError, "[unexpected error] " & message)
      error[] = message
      # we check only first error because subsequent ones may be meaningless
      raise newException(EParseError, "")
    else:
      doAssert warnings != nil, "unexpected RST warning '" & message & "'"
      warnings[].add message
  try:
    const filen = "input"

    proc myFindFile(filename: string): string =
      # we don't find any files in online mode:
      result = ""

    var (rst, _, _) = rstParse(input, filen, line=LineRstInit, column=ColRstInit,
                               rstOptions, myFindFile, testMsgHandler)
    result = treeRepr(rst)
  except EParseError as e:
    if e.msg != "":
      result = e.msg

suite "RST parsing":
  test "References are whitespace-neutral and case-insensitive":
    # refname is 'lexical-analysis', the same for all the 3 variants:
    check(dedent"""
        Lexical Analysis
        ================

        Ref. `Lexical Analysis`_ or `Lexical analysis`_ or `lexical analysis`_.
        """.toAst ==
      dedent"""
        rnInner
          rnHeadline  level=1
            rnLeaf  'Lexical'
            rnLeaf  ' '
            rnLeaf  'Analysis'
          rnParagraph
            rnLeaf  'Ref'
            rnLeaf  '.'
            rnLeaf  ' '
            rnInternalRef
              rnInner
                rnLeaf  'Lexical'
                rnLeaf  ' '
                rnLeaf  'Analysis'
              rnLeaf  'lexical-analysis'
            rnLeaf  ' '
            rnLeaf  'or'
            rnLeaf  ' '
            rnInternalRef
              rnInner
                rnLeaf  'Lexical'
                rnLeaf  ' '
                rnLeaf  'analysis'
              rnLeaf  'lexical-analysis'
            rnLeaf  ' '
            rnLeaf  'or'
            rnLeaf  ' '
            rnInternalRef
              rnInner
                rnLeaf  'lexical'
                rnLeaf  ' '
                rnLeaf  'analysis'
              rnLeaf  'lexical-analysis'
            rnLeaf  '.'
            rnLeaf  ' '
      """)

  test "RST quoted literal blocks":
    let expected =
      dedent"""
        rnInner
          rnLeaf  'Paragraph'
          rnLeaf  ':'
          rnLiteralBlock
            rnLeaf  '>x'
        """

    check(dedent"""
        Paragraph::

        >x""".toAst == expected)

    check(dedent"""
        Paragraph::

            >x""".toAst == expected)

  test "RST quoted literal blocks, :: at a separate line":
    let expected =
      dedent"""
        rnInner
          rnInner
            rnLeaf  'Paragraph'
          rnLiteralBlock
            rnLeaf  '>x
        >>y'
      """

    check(dedent"""
        Paragraph

        ::

        >x
        >>y""".toAst == expected)

    check(dedent"""
        Paragraph

        ::

          >x
          >>y""".toAst == expected)

  test "Markdown quoted blocks":
    check(dedent"""
        Paragraph.
        >x""".toAst ==
      dedent"""
        rnInner
          rnLeaf  'Paragraph'
          rnLeaf  '.'
          rnMarkdownBlockQuote
            rnMarkdownBlockQuoteItem  quotationDepth=1
              rnLeaf  'x'
      """)

    # bug #17987
    check(dedent"""
        foo https://github.com/nim-lang/Nim/issues/8258

        > bar""".toAst ==
      dedent"""
        rnInner
          rnInner
            rnLeaf  'foo'
            rnLeaf  ' '
            rnStandaloneHyperlink
              rnLeaf  'https://github.com/nim-lang/Nim/issues/8258'
          rnMarkdownBlockQuote
            rnMarkdownBlockQuoteItem  quotationDepth=1
              rnLeaf  'bar'
      """)

    let expected = dedent"""
        rnInner
          rnLeaf  'Paragraph'
          rnLeaf  '.'
          rnMarkdownBlockQuote
            rnMarkdownBlockQuoteItem  quotationDepth=1
              rnInner
                rnLeaf  'x1'
                rnLeaf  ' '
                rnLeaf  'x2'
            rnMarkdownBlockQuoteItem  quotationDepth=2
              rnInner
                rnLeaf  'y1'
                rnLeaf  ' '
                rnLeaf  'y2'
            rnMarkdownBlockQuoteItem  quotationDepth=1
              rnLeaf  'z'
        """

    check(dedent"""
        Paragraph.
        >x1 x2
        >>y1 y2
        >z""".toAst == expected)

    check(dedent"""
        Paragraph.
        > x1 x2
        >> y1 y2
        > z""".toAst == expected)

    check(dedent"""
        >x
        >y
        >z""".toAst ==
      dedent"""
        rnMarkdownBlockQuote
          rnMarkdownBlockQuoteItem  quotationDepth=1
            rnInner
              rnLeaf  'x'
              rnLeaf  ' '
              rnLeaf  'y'
              rnLeaf  ' '
              rnLeaf  'z'
      """)

    check(dedent"""
        > z
        > > >y
        """.toAst ==
      dedent"""
        rnMarkdownBlockQuote
          rnMarkdownBlockQuoteItem  quotationDepth=1
            rnLeaf  'z'
          rnMarkdownBlockQuoteItem  quotationDepth=3
            rnLeaf  'y'
        """)

  test "Markdown quoted blocks: lazy":
    let expected = dedent"""
        rnInner
          rnMarkdownBlockQuote
            rnMarkdownBlockQuoteItem  quotationDepth=2
              rnInner
                rnLeaf  'x'
                rnLeaf  ' '
                rnLeaf  'continuation1'
                rnLeaf  ' '
                rnLeaf  'continuation2'
          rnParagraph
            rnLeaf  'newParagraph'
      """
    check(dedent"""
        >>x
        continuation1
        continuation2

        newParagraph""".toAst == expected)

    check(dedent"""
        >> x
        continuation1
        continuation2

        newParagraph""".toAst == expected)

    # however mixing more than 1 non-lazy line and lazy one(s) splits quote
    # in our parser, which appeared the easiest way to handle such cases:
    var warnings = new seq[string]
    check(dedent"""
        >> x
        >> continuation1
        continuation2

        newParagraph""".toAst(warnings=warnings) ==
      dedent"""
        rnInner
          rnMarkdownBlockQuote
            rnMarkdownBlockQuoteItem  quotationDepth=2
              rnLeaf  'x'
            rnMarkdownBlockQuoteItem  quotationDepth=2
              rnInner
                rnLeaf  'continuation1'
                rnLeaf  ' '
                rnLeaf  'continuation2'
          rnParagraph
            rnLeaf  'newParagraph'
        """)
    check(warnings[] == @[
        "input(2, 1) Warning: RST style: two or more quoted lines " &
        "are followed by unquoted line 3"])

  test "Markdown quoted blocks: not lazy":
    # here is where we deviate from CommonMark specification: 'bar' below is
    # not considered as continuation of 2-level '>> foo' quote.
    check(dedent"""
        >>> foo
        > bar
        >> baz
        """.toAst() ==
      dedent"""
        rnMarkdownBlockQuote
          rnMarkdownBlockQuoteItem  quotationDepth=3
            rnLeaf  'foo'
          rnMarkdownBlockQuoteItem  quotationDepth=1
            rnLeaf  'bar'
          rnMarkdownBlockQuoteItem  quotationDepth=2
            rnLeaf  'baz'
        """)


  test "Markdown quoted blocks: inline markup works":
    check(dedent"""
        > hi **bold** text
        """.toAst == dedent"""
          rnMarkdownBlockQuote
            rnMarkdownBlockQuoteItem  quotationDepth=1
              rnInner
                rnLeaf  'hi'
                rnLeaf  ' '
                rnStrongEmphasis
                  rnLeaf  'bold'
                rnLeaf  ' '
                rnLeaf  'text'
        """)

  test "Markdown quoted blocks: blank line separator":
    let expected = dedent"""
      rnInner
        rnMarkdownBlockQuote
          rnMarkdownBlockQuoteItem  quotationDepth=1
            rnInner
              rnLeaf  'x'
              rnLeaf  ' '
              rnLeaf  'y'
        rnMarkdownBlockQuote
          rnMarkdownBlockQuoteItem  quotationDepth=1
            rnInner
              rnLeaf  'z'
              rnLeaf  ' '
              rnLeaf  't'
      """
    check(dedent"""
        >x
        >y

        > z
        > t""".toAst == expected)

    check(dedent"""
        >x
        y

        > z
         t""".toAst == expected)

  test "Markdown quoted blocks: nested body blocks/elements work #1":
    let expected = dedent"""
      rnMarkdownBlockQuote
        rnMarkdownBlockQuoteItem  quotationDepth=1
          rnBulletList
            rnBulletItem
              rnInner
                rnLeaf  'x'
            rnBulletItem
              rnInner
                rnLeaf  'y'
      """

    check(dedent"""
        > - x
          - y
        """.toAst == expected)

    # TODO: if bug #17340 point 28 is resolved then this may work:
    # check(dedent"""
    #     > - x
    #     - y
    #     """.toAst == expected)

    check(dedent"""
        > - x
        > - y
        """.toAst == expected)

    check(dedent"""
        >
        > - x
        >
        > - y
        >
        """.toAst == expected)

  test "Markdown quoted blocks: nested body blocks/elements work #2":
    let expected = dedent"""
      rnAdmonition  adType=note
        [nil]
        [nil]
        rnDefList
          rnDefItem
            rnDefName
              rnLeaf  'deflist'
              rnLeaf  ':'
            rnDefBody
              rnMarkdownBlockQuote
                rnMarkdownBlockQuoteItem  quotationDepth=2
                  rnInner
                    rnLeaf  'quote'
                    rnLeaf  ' '
                    rnLeaf  'continuation'
      """

    check(dedent"""
        .. Note:: deflist:
                    >> quote
                    continuation
        """.toAst == expected)

    check(dedent"""
        .. Note::
           deflist:
             >> quote
             continuation
        """.toAst == expected)

    check(dedent"""
        .. Note::
           deflist:
             >> quote
             >> continuation
        """.toAst == expected)

    # spaces are not significant between `>`:
    check(dedent"""
        .. Note::
           deflist:
             > > quote
             > > continuation
        """.toAst == expected)

  test "Markdown quoted blocks: de-indent handled well":
    check(dedent"""
        >
        >   - x
        >   - y
        >
        > Paragraph.
        """.toAst(rstOptions = preferRst) == dedent"""
          rnMarkdownBlockQuote
            rnMarkdownBlockQuoteItem  quotationDepth=1
              rnInner
                rnBlockQuote
                  rnBulletList
                    rnBulletItem
                      rnInner
                        rnLeaf  'x'
                    rnBulletItem
                      rnInner
                        rnLeaf  'y'
                rnParagraph
                  rnLeaf  'Paragraph'
                  rnLeaf  '.'
          """)

  let expectCodeBlock = dedent"""
      rnCodeBlock
        [nil]
        rnFieldList
          rnField
            rnFieldName
              rnLeaf  'default-language'
            rnFieldBody
              rnLeaf  'Nim'
        rnLiteralBlock
          rnLeaf  '
      let a = 1
      ```'
      """

  test "Markdown code blocks with more > 3 backticks":
    check(dedent"""
        ````
        let a = 1
        ```
        ````""".toAst == expectCodeBlock)

  test "Markdown code blocks with ~~~":
    check(dedent"""
        ~~~
        let a = 1
        ```
        ~~~""".toAst == expectCodeBlock)
    check(dedent"""
        ~~~~~
        let a = 1
        ```
        ~~~~~""".toAst == expectCodeBlock)

  test "Markdown code blocks with Nim-specific arguments":
    check(dedent"""
        ```nim number-lines=1 test
        let a = 1
        ```""".toAst ==
      dedent"""
        rnCodeBlock
          rnDirArg
            rnLeaf  'nim'
          rnFieldList
            rnField
              rnFieldName
                rnLeaf  'number-lines'
              rnFieldBody
                rnLeaf  '1'
            rnField
              rnFieldName
                rnLeaf  'test'
              rnFieldBody
          rnLiteralBlock
            rnLeaf  '
        let a = 1'
        """)

    check(dedent"""
        ```nim test = "nim c $1"  number-lines = 1
        let a = 1
        ```""".toAst ==
      dedent"""
        rnCodeBlock
          rnDirArg
            rnLeaf  'nim'
          rnFieldList
            rnField
              rnFieldName
                rnLeaf  'test'
              rnFieldBody
                rnLeaf  '"nim c $1"'
            rnField
              rnFieldName
                rnLeaf  'number-lines'
              rnFieldBody
                rnLeaf  '1'
          rnLiteralBlock
            rnLeaf  '
        let a = 1'
        """)

  test "additional indentation < 4 spaces is handled fine":
    check(dedent"""
        Indentation

          ```nim
            let a = 1
          ```""".toAst ==
      dedent"""
        rnInner
          rnParagraph
            rnLeaf  'Indentation'
          rnParagraph
            rnCodeBlock
              rnDirArg
                rnLeaf  'nim'
              [nil]
              rnLiteralBlock
                rnLeaf  '
          let a = 1'
      """)
      # | |
      # |  \ indentation of exactly two spaces before 'let a = 1'

  test "option list has priority over definition list":
    check(dedent"""
        --defusages
                      file
        -o            set
        """.toAst ==
      dedent"""
        rnOptionList
          rnOptionListItem  order=1
            rnOptionGroup
              rnLeaf  '--'
              rnLeaf  'defusages'
            rnDescription
              rnInner
                rnLeaf  'file'
          rnOptionListItem  order=2
            rnOptionGroup
              rnLeaf  '-'
              rnLeaf  'o'
            rnDescription
              rnLeaf  'set'
        """)

  test "items of 1 option list can be separated by blank lines":
    check(dedent"""
        -a  desc1

        -b  desc2
        """.toAst ==
      dedent"""
        rnOptionList
          rnOptionListItem  order=1
            rnOptionGroup
              rnLeaf  '-'
              rnLeaf  'a'
            rnDescription
              rnLeaf  'desc1'
          rnOptionListItem  order=2
            rnOptionGroup
              rnLeaf  '-'
              rnLeaf  'b'
            rnDescription
              rnLeaf  'desc2'
      """)

  test "option list has priority over definition list":
    check(dedent"""
        defName
            defBody

        -b  desc2
        """.toAst ==
      dedent"""
        rnInner
          rnDefList
            rnDefItem
              rnDefName
                rnLeaf  'defName'
              rnDefBody
                rnInner
                  rnLeaf  'defBody'
          rnOptionList
            rnOptionListItem  order=1
              rnOptionGroup
                rnLeaf  '-'
                rnLeaf  'b'
              rnDescription
                rnLeaf  'desc2'
      """)

  test "RST comment":
    check(dedent"""
        .. comment1
         comment2
        someParagraph""".toAst ==
      dedent"""
        rnLeaf  'someParagraph'
        """)

    check(dedent"""
        ..
         comment1
         comment2
        someParagraph""".toAst ==
      dedent"""
        rnLeaf  'someParagraph'
        """)

  test "check that additional line right after .. ends comment":
    check(dedent"""
        ..

         notAcomment1
         notAcomment2
        someParagraph""".toAst(rstOptions = preferRst) ==
      dedent"""
        rnInner
          rnBlockQuote
            rnInner
              rnLeaf  'notAcomment1'
              rnLeaf  ' '
              rnLeaf  'notAcomment2'
          rnParagraph
            rnLeaf  'someParagraph'
        """)

  test "check that additional line right after .. ends comment (Markdown mode)":
    # in Markdown small indentation does not matter so this should
    # just be split to 2 paragraphs.
    check(dedent"""
        ..

         notAcomment1
         notAcomment2
        someParagraph""".toAst ==
      dedent"""
        rnInner
          rnInner
            rnLeaf  'notAcomment1'
            rnLeaf  ' '
            rnLeaf  'notAcomment2'
          rnParagraph
            rnLeaf  'someParagraph'
        """)

  test "but blank lines after 2nd non-empty line don't end the comment":
    check(dedent"""
        ..
           comment1


         comment2
        someParagraph""".toAst ==
      dedent"""
        rnLeaf  'someParagraph'
        """)

  test "using .. as separator b/w directives and block quotes":
    check(dedent"""
        .. note:: someNote

        ..

          someBlockQuote""".toAst(rstOptions = preferRst) ==
      dedent"""
        rnInner
          rnAdmonition  adType=note
            [nil]
            [nil]
            rnLeaf  'someNote'
          rnBlockQuote
            rnInner
              rnLeaf  'someBlockQuote'
        """)

  test "no redundant blank lines in literal blocks":
    check(dedent"""
      Check::


        code

      """.toAst ==
      dedent"""
        rnInner
          rnLeaf  'Check'
          rnLeaf  ':'
          rnLiteralBlock
            rnLeaf  'code'
      """)

suite "RST tables":

  test "formatting in tables works":
    check(
      dedent"""
        =========  ===
        `build`    `a`
        =========  ===
        """.toAst ==
      dedent"""
        rnTable  colCount=2
          rnTableRow
            rnTableDataCell
              rnInlineCode
                rnDirArg
                  rnLeaf  'nim'
                [nil]
                rnLiteralBlock
                  rnLeaf  'build'
            rnTableDataCell
              rnInlineCode
                rnDirArg
                  rnLeaf  'nim'
                [nil]
                rnLiteralBlock
                  rnLeaf  'a'
      """)

  test "tables with slightly overflowed cells cause an error (1)":
    var error = new string
    check(
      dedent"""
        ======   ======
         Inputs  Output
        ======   ======
        """.toAst(error=error) == "")
    check(error[] == "input(2, 2) Error: Illformed table: " &
                     "this word crosses table column from the right")

  test "tables with slightly overflowed cells cause an error (2)":
    var error = new string
    check("" == dedent"""
      =====  =====  ======
      Input  Output
      =====  =====  ======
      False  False  False
      =====  =====  ======
      """.toAst(error=error))
    check(error[] == "input(2, 8) Error: Illformed table: " &
                     "this word crosses table column from the right")

  test "tables with slightly underflowed cells cause an error":
    var error = new string
    check("" == dedent"""
      =====  =====  ======
      Input Output
      =====  =====  ======
      False  False  False
      =====  =====  ======
      """.toAst(error=error))
    check(error[] == "input(2, 7) Error: Illformed table: " &
                     "this word crosses table column from the left")

  test "tables with unequal underlines should be reported (1)":
    var error = new string
    error[] = "none"
    check("" == dedent"""
      =====  ======
      Input  Output
      =====  ======
      False  False
      =====  =======
      """.toAst(error=error))
    check(error[] == "input(5, 14) Error: Illformed table: " &
                     "end of table column #2 should end at position 13")

  test "tables with unequal underlines should be reported (2)":
    var error = new string
    check("" == dedent"""
      =====  ======
      Input  Output
      =====  =======
      False  False
      =====  ======
      """.toAst(error=error))
    check(error[] == "input(3, 14) Error: Illformed table: " &
                     "end of table column #2 should end at position 13")

  test "tables with empty first cells":
    check(
      dedent"""
          = = =
          x y z
              t
          = = =
          """.toAst ==
      dedent"""
        rnTable  colCount=3
          rnTableRow
            rnTableDataCell
              rnLeaf  'x'
            rnTableDataCell
              rnInner
                rnLeaf  'y'
                rnLeaf  ' '
            rnTableDataCell
              rnInner
                rnLeaf  'z'
                rnLeaf  ' '
                rnLeaf  't'
        """)

  test "tables with spanning cells & separators":
    check(
      dedent"""
        =====  =====  ======
           Inputs     Output
        ------------  ------
          A      B    A or B
        =====  =====  ======
        False  False  False
        True   False  True
        -----  -----  ------
        False  True   True
        True   True   True
        =====  =====  ======
        """.toAst ==
      dedent"""
        rnTable  colCount=3
          rnTableRow
            rnTableHeaderCell  span=2
              rnLeaf  'Inputs'
            rnTableHeaderCell  span=1
              rnLeaf  'Output'
          rnTableRow  endsHeader
            rnTableHeaderCell
              rnLeaf  'A'
            rnTableHeaderCell
              rnLeaf  'B'
            rnTableHeaderCell
              rnInner
                rnLeaf  'A'
                rnLeaf  ' '
                rnLeaf  'or'
                rnLeaf  ' '
                rnLeaf  'B'
          rnTableRow
            rnTableDataCell
              rnLeaf  'False'
            rnTableDataCell
              rnLeaf  'False'
            rnTableDataCell
              rnLeaf  'False'
          rnTableRow
            rnTableDataCell  span=1
              rnLeaf  'True'
            rnTableDataCell  span=1
              rnLeaf  'False'
            rnTableDataCell  span=1
              rnLeaf  'True'
          rnTableRow
            rnTableDataCell
              rnLeaf  'False'
            rnTableDataCell
              rnLeaf  'True'
            rnTableDataCell
              rnLeaf  'True'
          rnTableRow
            rnTableDataCell
              rnLeaf  'True'
            rnTableDataCell
              rnLeaf  'True'
            rnTableDataCell
              rnLeaf  'True'
      """)

  test "tables with spanning cells with uneqal underlines cause an error":
    var error = new string
    check(
      dedent"""
        =====  =====  ======
           Inputs     Output
        ------------- ------
          A      B    A or B
        =====  =====  ======
        """.toAst(error=error) == "")
    check(error[] == "input(3, 1) Error: Illformed table: " &
                     "spanning underline does not match main table columns")

  let expTable = dedent"""
      rnTable  colCount=2
        rnTableRow
          rnTableDataCell
            rnLeaf  'Inputs'
          rnTableDataCell
            rnLeaf  'Output'
      """

  test "only tables with `=` columns specs are allowed (1)":
    var warnings = new seq[string]
    check(
      dedent"""
        ------  ------
        Inputs  Output
        ------  ------
        """.toAst(warnings=warnings) ==
      expTable)
    check(warnings[] ==
          @["input(1, 1) Warning: RST style: " &
              "only tables with `=` columns specification are allowed",
            "input(3, 1) Warning: RST style: " &
              "only tables with `=` columns specification are allowed"])

  test "only tables with `=` columns specs are allowed (2)":
    var warnings = new seq[string]
    check(
      dedent"""
        ======  ======
        Inputs  Output
        ~~~~~~  ~~~~~~
        """.toAst(warnings=warnings) ==
      expTable)
    check(warnings[] ==
          @["input(3, 1) Warning: RST style: "&
              "only tables with `=` columns specification are allowed"])


suite "RST indentation":
  test "nested bullet lists":
    let input = dedent """
      * - bullet1
        - bullet2
      * - bullet3
        - bullet4
      """
    let output = input.toAst
    check(output == dedent"""
      rnBulletList
        rnBulletItem
          rnBulletList
            rnBulletItem
              rnInner
                rnLeaf  'bullet1'
            rnBulletItem
              rnInner
                rnLeaf  'bullet2'
        rnBulletItem
          rnBulletList
            rnBulletItem
              rnInner
                rnLeaf  'bullet3'
            rnBulletItem
              rnInner
                rnLeaf  'bullet4'
      """)

  test "nested markup blocks":
    let input = dedent"""
      #) .. Hint:: .. Error:: none
      #) .. Warning:: term0
                        Definition0
      #) some
         paragraph1
      #) term1
           Definition1
         term2
           Definition2
    """
    check(input.toAst == dedent"""
      rnEnumList  labelFmt=1)
        rnEnumItem
          rnAdmonition  adType=hint
            [nil]
            [nil]
            rnAdmonition  adType=error
              [nil]
              [nil]
              rnLeaf  'none'
        rnEnumItem
          rnAdmonition  adType=warning
            [nil]
            [nil]
            rnDefList
              rnDefItem
                rnDefName
                  rnLeaf  'term0'
                rnDefBody
                  rnInner
                    rnLeaf  'Definition0'
        rnEnumItem
          rnInner
            rnLeaf  'some'
            rnLeaf  ' '
            rnLeaf  'paragraph1'
        rnEnumItem
          rnDefList
            rnDefItem
              rnDefName
                rnLeaf  'term1'
              rnDefBody
                rnInner
                  rnLeaf  'Definition1'
            rnDefItem
              rnDefName
                rnLeaf  'term2'
              rnDefBody
                rnInner
                  rnLeaf  'Definition2'
      """)

  test "code-block parsing":
    let input1 = dedent"""
      .. code-block:: nim
          :test: "nim c $1"

        template additive(typ: typedesc) =
          discard
      """
    let input2 = dedent"""
      .. code-block:: nim
        :test: "nim c $1"

        template additive(typ: typedesc) =
          discard
      """
    let input3 = dedent"""
      .. code-block:: nim
         :test: "nim c $1"
         template additive(typ: typedesc) =
           discard
      """
    let inputWrong = dedent"""
      .. code-block:: nim
       :test: "nim c $1"

         template additive(typ: typedesc) =
           discard
      """
    let ast = dedent"""
      rnCodeBlock
        rnDirArg
          rnLeaf  'nim'
        rnFieldList
          rnField
            rnFieldName
              rnLeaf  'test'
            rnFieldBody
              rnInner
                rnLeaf  '"'
                rnLeaf  'nim'
                rnLeaf  ' '
                rnLeaf  'c'
                rnLeaf  ' '
                rnLeaf  '$'
                rnLeaf  '1'
                rnLeaf  '"'
          rnField
            rnFieldName
              rnLeaf  'default-language'
            rnFieldBody
              rnLeaf  'Nim'
        rnLiteralBlock
          rnLeaf  'template additive(typ: typedesc) =
        discard'
      """
    check input1.toAst == ast
    check input2.toAst == ast
    check input3.toAst == ast
    # "template..." should be parsed as a definition list attached to ":test:":
    check inputWrong.toAst != ast

suite "Warnings":
  test "warnings for broken footnotes/links/substitutions":
    let input = dedent"""
      firstParagraph

      footnoteRef [som]_

      link `a broken Link`_

      substitution |undefined subst|

      link short.link_

      lastParagraph
      """
    var warnings = new seq[string]
    let output = input.toAst(warnings=warnings)
    check(warnings[] == @[
        "input(3, 14) Warning: broken link 'citation-som'",
        "input(5, 7) Warning: broken link 'a broken Link'",
        "input(7, 15) Warning: unknown substitution 'undefined subst'",
        "input(9, 6) Warning: broken link 'short.link'"
        ])

  test "With include directive and blank lines at the beginning":
    "other.rst".writeFile(dedent"""


        firstParagraph

        here brokenLink_""")
    let input = ".. include:: other.rst"
    var warnings = new seq[string]
    let output = input.toAst(warnings=warnings)
    check warnings[] == @["other.rst(5, 6) Warning: broken link 'brokenLink'"]
    check(output == dedent"""
      rnInner
        rnParagraph
          rnLeaf  'firstParagraph'
        rnParagraph
          rnLeaf  'here'
          rnLeaf  ' '
          rnRef
            rnLeaf  'brokenLink'
      """)
    removeFile("other.rst")

  test "warnings for ambiguous links (references + anchors)":
    # Reference like `x`_ generates a link alias x that may clash with others
    let input = dedent"""
      Manual reference: `foo <#foo,string,string>`_

      .. _foo:

      Paragraph.

      Ref foo_
      """
    var warnings = new seq[string]
    let output = input.toAst(warnings=warnings)
    check(warnings[] == @[
      dedent """
      input(7, 5) Warning: ambiguous doc link `foo`
        clash:
          (3, 8): (manual directive anchor)
          (1, 45): (implicitly-generated hyperlink alias)"""
    ])
    # reference should be resolved to the manually set anchor:
    check(output ==
      dedent"""
        rnInner
          rnParagraph
            rnLeaf  'Manual'
            rnLeaf  ' '
            rnLeaf  'reference'
            rnLeaf  ':'
            rnLeaf  ' '
            rnHyperlink
              rnInner
                rnLeaf  'foo'
              rnInner
                rnLeaf  '#foo,string,string'
          rnParagraph  anchor='foo'
            rnLeaf  'Paragraph'
            rnLeaf  '.'
          rnParagraph
            rnLeaf  'Ref'
            rnLeaf  ' '
            rnInternalRef
              rnInner
                rnLeaf  'foo'
              rnLeaf  'foo'
            rnLeaf  ' '
      """)

suite "RST include directive":
  test "Include whole":
    "other.rst".writeFile("**test1**")
    let input = ".. include:: other.rst"
    doAssert "<strong>test1</strong>" == rstToHtml(input, {roSandboxDisabled}, defaultConfig())
    removeFile("other.rst")

  test "Include starting from":
    "other.rst".writeFile("""
And this should **NOT** be visible in `docs.html`
OtherStart
*Visible*
""")

    let input = """
.. include:: other.rst
             :start-after: OtherStart
"""
    check "<em>Visible</em>" == rstToHtml(input, {roSandboxDisabled}, defaultConfig())
    removeFile("other.rst")

  test "Include everything before":
    "other.rst".writeFile("""
*Visible*
OtherEnd
And this should **NOT** be visible in `docs.html`
""")

    let input = """
.. include:: other.rst
             :end-before: OtherEnd
"""
    doAssert "<em>Visible</em>" == rstToHtml(input, {roSandboxDisabled}, defaultConfig())
    removeFile("other.rst")


  test "Include everything between":
    "other.rst".writeFile("""
And this should **NOT** be visible in `docs.html`
OtherStart
*Visible*
OtherEnd
And this should **NOT** be visible in `docs.html`
""")

    let input = """
.. include:: other.rst
             :start-after: OtherStart
             :end-before: OtherEnd
"""
    check "<em>Visible</em>" == rstToHtml(input, {roSandboxDisabled}, defaultConfig())
    removeFile("other.rst")


  test "Ignore premature ending string":
    "other.rst".writeFile("""

OtherEnd
And this should **NOT** be visible in `docs.html`
OtherStart
*Visible*
OtherEnd
And this should **NOT** be visible in `docs.html`
""")

    let input = """
.. include:: other.rst
             :start-after: OtherStart
             :end-before: OtherEnd
"""
    doAssert "<em>Visible</em>" == rstToHtml(input, {roSandboxDisabled}, defaultConfig())
    removeFile("other.rst")

suite "RST escaping":
  test "backspaces":
    check("""\ this""".toAst == dedent"""
      rnLeaf  'this'
      """)

    check("""\\ this""".toAst == dedent"""
      rnInner
        rnLeaf  '\'
        rnLeaf  ' '
        rnLeaf  'this'
      """)

    check("""\\\ this""".toAst == dedent"""
      rnInner
        rnLeaf  '\'
        rnLeaf  'this'
      """)

    check("""\\\\ this""".toAst == dedent"""
      rnInner
        rnLeaf  '\'
        rnLeaf  '\'
        rnLeaf  ' '
        rnLeaf  'this'
      """)

suite "RST inline markup":
  test "* and ** surrounded by spaces are not inline markup":
    check("a * b * c ** d ** e".toAst == dedent"""
      rnInner
        rnLeaf  'a'
        rnLeaf  ' '
        rnLeaf  '*'
        rnLeaf  ' '
        rnLeaf  'b'
        rnLeaf  ' '
        rnLeaf  '*'
        rnLeaf  ' '
        rnLeaf  'c'
        rnLeaf  ' '
        rnLeaf  '**'
        rnLeaf  ' '
        rnLeaf  'd'
        rnLeaf  ' '
        rnLeaf  '**'
        rnLeaf  ' '
        rnLeaf  'e'
      """)

  test "end-string has repeating symbols":
    check("*emphasis content****".toAst == dedent"""
      rnEmphasis
        rnLeaf  'emphasis'
        rnLeaf  ' '
        rnLeaf  'content'
        rnLeaf  '***'
      """)

    check("""*emphasis content\****""".toAst == dedent"""
      rnEmphasis
        rnLeaf  'emphasis'
        rnLeaf  ' '
        rnLeaf  'content'
        rnLeaf  '*'
        rnLeaf  '**'
      """)  # exact configuration of leafs with * is not really essential,
            # only total number of * is essential

    check("**strong content****".toAst == dedent"""
      rnStrongEmphasis
        rnLeaf  'strong'
        rnLeaf  ' '
        rnLeaf  'content'
        rnLeaf  '**'
      """)

    check("""**strong content*\****""".toAst == dedent"""
      rnStrongEmphasis
        rnLeaf  'strong'
        rnLeaf  ' '
        rnLeaf  'content'
        rnLeaf  '*'
        rnLeaf  '*'
        rnLeaf  '*'
      """)

    check("``lit content`````".toAst == dedent"""
      rnInlineLiteral
        rnLeaf  'lit'
        rnLeaf  ' '
        rnLeaf  'content'
        rnLeaf  '```'
      """)

  test "interpreted text parsing: code fragments":
    check(dedent"""
        .. default-role:: option

        `--gc:refc`""".toAst ==
      dedent"""
        rnInner
          rnDefaultRole
            rnDirArg
              rnLeaf  'option'
            [nil]
            [nil]
          rnParagraph
            rnCodeFragment
              rnInner
                rnLeaf  '--'
                rnLeaf  'gc'
                rnLeaf  ':'
                rnLeaf  'refc'
              rnLeaf  'option'
        """)

  test """interpreted text can be ended with \` """:
    let output = (".. default-role:: literal\n" & """`\``""").toAst
    check(output.endsWith """
  rnParagraph
    rnInlineLiteral
      rnLeaf  '`'""" & "\n")

    let output2 = """`\``""".toAst
    check(output2 == dedent"""
      rnInlineCode
        rnDirArg
          rnLeaf  'nim'
        [nil]
        rnLiteralBlock
          rnLeaf  '`'
      """)

    let output3 = """`proc \`+\``""".toAst
    check(output3 == dedent"""
      rnInlineCode
        rnDirArg
          rnLeaf  'nim'
        [nil]
        rnLiteralBlock
          rnLeaf  'proc `+`'
      """)

    check("""`\\`""".toAst ==
      dedent"""
        rnInlineCode
          rnDirArg
            rnLeaf  'nim'
          [nil]
          rnLiteralBlock
            rnLeaf  '\\'
        """)

  test "Markdown-style code/backtick":
    # no whitespace is required before `
    check("`try`...`except`".toAst ==
      dedent"""
        rnInner
          rnInlineCode
            rnDirArg
              rnLeaf  'nim'
            [nil]
            rnLiteralBlock
              rnLeaf  'try'
          rnLeaf  '...'
          rnInlineCode
            rnDirArg
              rnLeaf  'nim'
            [nil]
            rnLiteralBlock
              rnLeaf  'except'
        """)


  test """inline literals can contain \ anywhere""":
    check("""``\``""".toAst == dedent"""
      rnInlineLiteral
        rnLeaf  '\'
      """)

    check("""``\\``""".toAst == dedent"""
      rnInlineLiteral
        rnLeaf  '\'
        rnLeaf  '\'
      """)

    check("""``\```""".toAst == dedent"""
      rnInlineLiteral
        rnLeaf  '\'
        rnLeaf  '`'
      """)

    check("""``\\```""".toAst == dedent"""
      rnInlineLiteral
        rnLeaf  '\'
        rnLeaf  '\'
        rnLeaf  '`'
      """)

    check("""``\````""".toAst == dedent"""
      rnInlineLiteral
        rnLeaf  '\'
        rnLeaf  '`'
        rnLeaf  '`'
      """)

  test "references with _ at the end":
    check(dedent"""
      .. _lnk: https

      lnk_""".toAst ==
      dedent"""
        rnHyperlink
          rnInner
            rnLeaf  'lnk'
          rnInner
            rnLeaf  'https'
      """)

  test "not a hyper link":
    check(dedent"""
      .. _lnk: https

      lnk___""".toAst ==
      dedent"""
        rnInner
          rnLeaf  'lnk'
          rnLeaf  '___'
      """)

  test "no punctuation in the end of a standalone URI is allowed":
    check(dedent"""
        [see (http://no.org)], end""".toAst ==
      dedent"""
        rnInner
          rnLeaf  '['
          rnLeaf  'see'
          rnLeaf  ' '
          rnLeaf  '('
          rnStandaloneHyperlink
            rnLeaf  'http://no.org'
          rnLeaf  ')'
          rnLeaf  ']'
          rnLeaf  ','
          rnLeaf  ' '
          rnLeaf  'end'
        """)

    # but `/` at the end is OK
    check(
      dedent"""
        See http://no.org/ end""".toAst ==
      dedent"""
        rnInner
          rnLeaf  'See'
          rnLeaf  ' '
          rnStandaloneHyperlink
            rnLeaf  'http://no.org/'
          rnLeaf  ' '
          rnLeaf  'end'
        """)

    # a more complex URL with some made-up ending '&='.
    # Github Markdown would include final &= and
    # so would rst2html.py in contradiction with RST spec.
    check(
      dedent"""
        See https://www.google.com/url?sa=t&source=web&cd=&cad=rja&url=https%3A%2F%2Fnim-lang.github.io%2FNim%2Frst.html%23features&usg=AO&= end""".toAst ==
      dedent"""
        rnInner
          rnLeaf  'See'
          rnLeaf  ' '
          rnStandaloneHyperlink
            rnLeaf  'https://www.google.com/url?sa=t&source=web&cd=&cad=rja&url=https%3A%2F%2Fnim-lang.github.io%2FNim%2Frst.html%23features&usg=AO'
          rnLeaf  '&'
          rnLeaf  '='
          rnLeaf  ' '
          rnLeaf  'end'
        """)

  test "URL with balanced parentheses (Markdown rule)":
    # 2 balanced parens, 1 unbalanced:
    check(dedent"""
        https://en.wikipedia.org/wiki/APL_((programming_language)))""".toAst ==
      dedent"""
        rnInner
          rnStandaloneHyperlink
            rnLeaf  'https://en.wikipedia.org/wiki/APL_((programming_language))'
          rnLeaf  ')'
      """)

    # the same for Markdown-style link:
    check(dedent"""
        [foo [bar]](https://en.wikipedia.org/wiki/APL_((programming_language))))""".toAst ==
      dedent"""
        rnInner
          rnHyperlink
            rnLeaf  'foo [bar]'
            rnLeaf  'https://en.wikipedia.org/wiki/APL_((programming_language))'
          rnLeaf  ')'
      """)

    # unbalanced (here behavior is more RST-like actually):
    check(dedent"""
        https://en.wikipedia.org/wiki/APL_(programming_language(""".toAst ==
      dedent"""
        rnInner
          rnStandaloneHyperlink
            rnLeaf  'https://en.wikipedia.org/wiki/APL_(programming_language'
          rnLeaf  '('
      """)

    # unbalanced [, but still acceptable:
    check(dedent"""
        [my {link example](http://example.com/bracket_(symbol_[))""".toAst ==
      dedent"""
        rnHyperlink
          rnLeaf  'my {link example'
          rnLeaf  'http://example.com/bracket_(symbol_[)'
      """)

  test "not a Markdown link":
    # bug #17340 (27) `f` will be considered as a protocol and blocked as unsafe
    var warnings = new seq[string]
    check("[T](f: var Foo)".toAst(warnings = warnings) ==
      dedent"""
        rnInner
          rnLeaf  '['
          rnLeaf  'T'
          rnLeaf  ']'
          rnLeaf  '('
          rnLeaf  'f'
          rnLeaf  ':'
          rnLeaf  ' '
          rnLeaf  'var'
          rnLeaf  ' '
          rnLeaf  'Foo'
          rnLeaf  ')'
      """)
    check(warnings[] == @["input(1, 5) Warning: broken link 'f'"])
