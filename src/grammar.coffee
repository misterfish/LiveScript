# The Coco parser is generated by [Jison](http://github.com/zaach/jison)
# from this grammar file. Jison is a bottom-up parser generator, similar in
# style to [Bison](http://www.gnu.org/software/bison), implemented in JavaScript.
# It can recognize [LALR(1), LR(0), SLR(1), and LR(1)](http://en.wikipedia.org/wiki/LR_grammar)
# type grammars. To create the Jison parser, we list the pattern to match
# on the left-hand side, and the action to take (usually the creation of syntax
# tree nodes) on the right. As the parser runs, it
# shifts tokens from our token stream, from left to right, and
# [attempts to match](http://en.wikipedia.org/wiki/Bottom-up_parsing)
# the token sequence against the rules below. When a match can be made, it
# reduces into the [nonterminal](http://en.wikipedia.org/wiki/Terminal_and_nonterminal_symbols)
# (the enclosing name at the top), and we proceed from there.
#
# If you run the `cake build:parser` command, Jison constructs a parse table
# from our rules and saves it into `lib/parser.js`.

# The only dependency is on the **Jison.Parser**.
{Parser} = require 'jison'

# Jison DSL
# ---------

# Since we're going to be wrapped in a function by Jison in any case, if our
# action immediately returns a value, we can optimize by removing the function
# wrapper and just returning the value directly.
unwrap = /^function\s*\(\)\s*\{\s*return\s*([\s\S]*);\s*\}/

# Our handy DSL for Jison grammar generation, thanks to
# [Tim Caswell](http://github.com/creationix). For every rule in the grammar,
# we pass the pattern-defining string, the action to run, and extra options,
# optionally. If no action is specified, we simply pass the value of the
# previous nonterminal.
o = (patternString, action, options) ->
  patternString .= replace /\s{2,}/g, ' '
  return [patternString, '$$ = $1;', options] unless action
  action  = if match = unwrap.exec action then match[1] else "(#{action}())"
  action .= replace /\b(?:[A-Z]|mix\b)/g, 'yy.$&'
  [patternString, "$$ = #{action};", options]

# Grammatical Rules
# -----------------

# In all of the rules that follow, you'll see the name of the nonterminal as
# the key to a list of alternative matches. With each match's action, the
# dollar-sign variables are provided by Jison as references to the value of
# their numeric position, so in this rule:
#
#     "Expression UNLESS Expression"
#
# `$1` would be the value of the first `Expression`, `$2` would be the token
# for the `UNLESS` terminal, and `$3` would be the value of the second
# `Expression`.
grammar =

  # The **Root** is the top-level node in the syntax tree. Since we parse bottom-up,
  # all parsing must end here.
  Root: [
    o '', -> Expressions()
    o 'Body'
    o 'Block TERMINATOR'
  ]

  # Any list of statements and expressions, separated by line breaks or semicolons.
  Body: [
    o 'Line',                 -> Expressions $1
    o 'Body TERMINATOR Line', -> $1.append $3
    o 'Body TERMINATOR'
  ]
  # Expressions and statements, which make up a line in a body.
  Line: [
    o 'Expression'
    o 'Statement'
  ]

  # Pure statements which cannot be expressions.
  Statement: [
    o 'RETURN',            -> Return()
    o 'RETURN Expression', -> Return $2
    o 'THROW  Expression', -> Throw $2
    o 'STATEMENT',         -> Literal $1
    o 'HERECOMMENT',       -> Comment $1
  ]

  # All the different types of expressions in our language. The basic unit of
  # Coco is the **Expression** -- everything that can be an expression
  # is one. Expressions serve as the building blocks of many other rules, making
  # them somewhat circular.
  Expression: [
    o 'Value'

    o 'Code'
    o 'FUNCTION Code',            -> mix $2, statement: true
    o 'FUNCTION IDENTIFIER Code', -> mix $3, statement: true, name: $2

    # Arithmetic and logical operators, working on one or more operands.
    # Here they are grouped by order of precedence. The actual precedence rules
    # are defined at the bottom of the page. It would be shorter if we could
    # combine most of these rules into a single generic *Operand OpSymbol Operand*
    # -type rule, but in order to make the precedence binding possible, separate
    # rules are necessary.
    o 'UNARY      Expression',            -> Op $1, $2
    o 'PLUS_MINUS Expression',           (-> Op $1, $2), prec: 'UNARY'

    o 'CREMENT SimpleAssignable',         -> Op $1, $2
    o 'SimpleAssignable CREMENT',         -> Op $2, $1, null, true

    o 'Expression ?',                     -> Existence $1

    o 'Expression PLUS_MINUS Expression', -> Op $2, $1, $3
    o 'Expression MATH       Expression', -> Op $2, $1, $3
    o 'Expression SHIFT      Expression', -> Op $2, $1, $3
    o 'Expression COMPARE    Expression', -> Op $2, $1, $3
    o 'Expression LOGIC      Expression', -> Op $2, $1, $3
    o 'Expression IMPORT     Expression', -> Import $1, $3, $2
    o 'Expression RELATION   Expression', ->
      if $2.charAt(0) is '!'
      then Op($2.slice(1), $1, $3).invert()
      else Op $2, $1, $3

    o 'Assignable ASSIGN Expression',                -> Assign $1, $3, $2
    o 'Assignable ASSIGN INDENT Expression OUTDENT', -> Assign $1, $4, $2
    o 'SimpleAssignable COMPOUND_ASSIGN
       Expression',                                  -> Assign $1, $3, $2
    o 'SimpleAssignable COMPOUND_ASSIGN
       INDENT Expression OUTDENT',                   -> Assign $1, $4, $2

    o 'SimpleAssignable EXTENDS Expression', -> Extends $1, $3

    # Array, object, and range comprehensions, at the most generic level.
    # Comprehensions can either be normal, with a block of expressions to execute,
    # or postfix, with a single expression.
    o 'LoopHead   Block',    -> $1.addBody $2
    o 'Statement  LoopHead', -> $2.addBody Expressions $1
    o 'Expression LoopHead', -> $2.addBody Expressions $1

    # The full complement of `if` expressions,
    # including postfix one-liner `if` and `unless`.
    o 'IfBlock'
    o 'Statement  POST_IF Expression', ->
      If $3, Expressions($1), name: $2, statement: true
    o 'Expression POST_IF Expression', ->
      If $3, Expressions($1), name: $2, statement: true

    o 'SWITCH Expression Cases',               -> Switch $2, $3
    o 'SWITCH Expression Cases DEFAULT Block', -> Switch $2, $3, $5
    o 'SWITCH Cases',                          -> Switch null, $2
    o 'SWITCH Cases DEFAULT Block',            -> Switch null, $2, $4

    o 'TRY Block',                                      -> Try $2
    o 'TRY Block CATCH IDENTIFIER Block',               -> Try $2, $4, $5
    o 'TRY Block                        FINALLY Block', -> Try $2, null, null, $4
    o 'TRY Block CATCH IDENTIFIER Block FINALLY Block', -> Try $2, $4, $5, $7

    # Class definitions have optional bodies of prototype property assignments,
    # and optional references to the superclass.
    o 'CLASS',                                      -> Class()
    o 'CLASS Block',                                -> Class null, null, $2
    o 'CLASS EXTENDS Value',                        -> Class null, $3
    o 'CLASS EXTENDS Value Block',                  -> Class null, $3, $4
    o 'CLASS SimpleAssignable',                     -> Class $2
    o 'CLASS SimpleAssignable Block',               -> Class $2, null, $3
    o 'CLASS SimpleAssignable EXTENDS Value',       -> Class $2, $4
    o 'CLASS SimpleAssignable EXTENDS Value Block', -> Class $2, $4, $5
  ]

  # An indented block of expressions. Note that the [Rewriter](rewriter.html)
  # will convert some postfix forms into blocks for us, by adjusting the
  # token stream.
  Block: [
    o 'INDENT Body OUTDENT', -> $2
    o 'INDENT      OUTDENT', -> Expressions()
  ]

  # A literal identifier, a variable name or property.
  Identifier: [
    o 'IDENTIFIER', -> Literal $1
  ]

  # All of our immediate values. These can (in general), be passed straight
  # through and printed to JavaScript.
  Literal: [
    o 'STRNUM',  -> Literal $1
    o 'THIS',    -> Literal 'this'
    o 'LITERAL', -> if $1 is 'void' then Op 'void', Literal 8 else Literal $1
  ]

  # Assignment when it happens within an object literal. The difference from
  # the ordinary **Assign** is that these allow numbers and strings as keys.
  AssignObj: [
    o 'ObjAssignable',              -> Value $1
    o 'ObjAssignable : Expression', -> Assign Value($1), $3, ':'
    o 'ObjAssignable :
       INDENT Expression OUTDENT',  -> Assign Value($1), $4, ':'
    o 'Identifier    ...',          -> Splat $1
    o 'Parenthetical ...',          -> Splat $1
    o 'ThisProperty'
    o 'HERECOMMENT',                -> Comment $1
  ]
  ObjAssignable: [
    o 'STRNUM', -> Literal $1
    o 'Identifier'
    o 'Parenthetical'
  ]

  # The **Code** node is the function literal. It's defined by an indented block
  # of **Expressions** preceded by a function arrow, with an optional parameter
  # list.
  Code: [
    o 'PARAM_START ParamList PARAM_END
       FUNC_ARROW Block', -> Code $2, $5, $4
    o 'FUNC_ARROW Block', -> Code [], $2, $1
  ]
  # The list of parameters that a function accepts can be of any length.
  ParamList: [
    o '',                  -> []
    o 'Param',             -> [$1]
    o 'ParamList , Param', -> $1.concat $3
  ]
  # A single parameter in a function definition can be ordinary, or a splat
  # that hoovers up the remaining arguments.
  Param: [
    o 'ParamVar',                   -> Param $1
    o 'ParamVar ...',               -> Param $1, null, true
    o 'ParamVar ASSIGN Expression', -> Param $1, $3
  ]
  ParamVar: [
    o 'Identifier'
    o 'ThisProperty'
    o 'Array'
    o 'Object'
  ]

  # Variables and properties that can be assigned to.
  SimpleAssignable: [
    o 'Identifier'
    o 'ThisProperty'
    o 'Value Accessor', -> $1.append $2
    o 'SUPER',          -> Super()
  ]

  # Everything that can be assigned to.
  Assignable: [
    o 'SimpleAssignable'
    o 'Array'
    o 'Object'
  ]

  # The types of things that can be treated as values -- assigned to, invoked
  # as functions, indexed into, named as a class, etc.
  Value: [
    o 'Assignable',    -> Value $1
    o 'Literal',       -> Value $1
    o 'Parenthetical', -> Value $1
    o 'Value CALL_START                  CALL_END', -> Value Call $1, []  , $2
    o 'Value CALL_START ...              CALL_END', -> Value Call $1, null, $2
    o 'Value CALL_START ArgList OptComma CALL_END', -> Value Call $1, $3  , $2
  ]

  # The general group of accessors into an object.
  Accessor: [
    o 'ACCESS Identifier',                -> Access $2, $1
    o 'INDEX_START Expression INDEX_END', -> Index  $2, $1
  ]

  # A reference to a property on `this`.
  ThisProperty: [
    o 'THISPROP', -> Value Literal('this'), [Access Literal $1], 'this'
  ]

  # An optional, trailing comma.
  OptComma: [
    o ''
    o ','
  ]

  # In Coco, an object literal is simply a list of assignments.
  Object: [
    o '{ AssignList OptComma }', -> Obj $2
  ]

  # Assignment of properties within an object literal can be separated by
  # comma, as in JavaScript, or simply by newline.
  AssignList: [
    o '',                                                       -> []
    o 'AssignObj',                                              -> [$1]
    o 'AssignList , AssignObj',                                 -> $1.concat $3
    o 'AssignList OptComma TERMINATOR AssignObj',               -> $1.concat $4
    o 'AssignList OptComma INDENT AssignList OptComma OUTDENT', -> $1.concat $4
  ]

  # The array literal.
  Array: [
    o '[                  ]', -> Arr []
    o '[ ArgList OptComma ]', -> Arr $2
  ]

  # The **ArgList** is both the list of objects passed into a function call,
  # as well as the contents of an array literal
  # (i.e. comma-separated expressions). Newlines work as well.
  ArgList: [
    o 'Arg',                                              -> [$1]
    o 'ArgList , Arg',                                    -> $1.concat $3
    o 'ArgList OptComma TERMINATOR Arg',                  -> $1.concat $4
    o 'INDENT ArgList OptComma OUTDENT',                  -> $2
    o 'ArgList OptComma INDENT ArgList OptComma OUTDENT', -> $1.concat $4
  ]
  Arg: [
    o 'Expression'
    o 'Expression ...', -> Splat $1
  ]

  # Parenthetical expressions. Note that the **Parenthetical** is a **Value**,
  # not an **Expression**, so if you need to use an expression in a place
  # where only values are accepted, wrapping it in parentheses will always do
  # the trick.
  Parenthetical: [
    o '( Body )',                -> Parens $2
    o '( INDENT Body OUTDENT )', -> Parens $3
  ]

  # The source of a comprehension is an array or object with an optional guard
  # clause. If it's an array comprehension, you can also choose to step through
  # in fixed-size increments.
  LoopHead: [
    o 'FOR Assignable              FOROF Expression'
    , -> mix For(), name: $2,            source: $4
    o 'FOR Assignable , IDENTIFIER FOROF Expression'
    , -> mix For(), name: $2, index: $4, source: $6
    o 'FOR Assignable              FOROF Expression BY Expression'
    , -> mix For(), name: $2,            source: $4, step: $6
    o 'FOR Assignable , IDENTIFIER FOROF Expression BY Expression'
    , -> mix For(), name: $2, index: $4, source: $6, step: $8

    o 'FOR IDENTIFIER              FORIN Expression'
    , -> mix For(), object: true, own: !$1, index: $2,           source: $4
    o 'FOR Assignable , Assignable FORIN Expression'
    , -> mix For(), object: true, own: !$1, index: $2, name: $4, source: $6

    o 'FOR IDENTIFIER FROM Expression TO Expression'
    , -> mix For(), index: $2, from: $4, op: $5, to: $6
    o 'FOR IDENTIFIER FROM Expression TO Expression BY Expression'
    , -> mix For(), index: $2, from: $4, op: $5, to: $6, step : $8

    o 'FOR EVER',         -> While()
    o 'WHILE Expression', -> While $2, $1
  ]

  Cases: [
    o 'Case',       -> [$1]
    o 'Cases Case', -> $1.concat $2
  ]
  Case: [
    o 'CASE SimpleArgs Block', -> Case $2, $3
  ]
  # Just simple, comma-separated, required arguments (no fancy syntax). We need
  # this to be separate from the **ArgList** for use in **Switch** blocks, where
  # having the newlines wouldn't make sense.
  SimpleArgs: [
    o 'Expression',              -> [$1]
    o 'SimpleArgs , Expression', -> $1.concat $3
  ]

  # The most basic form of *if* is a condition and an action. The following
  # if-related rules are broken up along these lines in order to avoid
  # ambiguity.
  IfBlock: [
    o 'IF Expression Block',              -> If $2, $3, name: $1
    o 'IfBlock ELSE IF Expression Block', -> $1.addElse If $4, $5, name: $3
    o 'IfBlock ELSE Block',               -> $1.addElse $3
  ]

# Precedence
# ----------

# Operators at the top of this list have higher precedence than the ones lower
# down. Following these rules is what makes `2 + 3 * 4` parse as:
#
#     2 + (3 * 4)
#
# And not:
#
#     (2 + 3) * 4
operators = [
  <[ left      CALL_START CALL_END          ]>
  <[ nonassoc  CREMENT                      ]>
  <[ left      ?                            ]>
  <[ right     UNARY                        ]>
  <[ left      MATH                         ]>
  <[ left      PLUS_MINUS                   ]>
  <[ left      SHIFT                        ]>
  <[ left      RELATION IMPORT              ]>
  <[ left      COMPARE                      ]>
  <[ left      LOGIC                        ]>
  <[ nonassoc  INDENT OUTDENT               ]>
  <[ right     : ASSIGN COMPOUND_ASSIGN
               RETURN THROW EXTENDS         ]>
  <[ right     IF ELSE SWITCH CASE DEFAULT
               CLASS FORIN FOROF FROM TO BY ]>
  <[ left      POST_IF FOR WHILE            ]>
]

# Wrapping Up
# -----------

# Finally, now what we have our **grammar** and our **operators**, we can create
# our **Jison.Parser**. We do this by processing all of our rules, recording all
# terminals (every symbol which does not appear as the name of a rule above)
# as "tokens".
tokens = []
for name, alternatives in grammar
  grammar[name] = for alt of alternatives
    for token of alt[0].split ' '
      tokens.push token unless grammar[token]
    alt[1] = "return #{alt[1]}" if name is 'Root'
    alt

# Initialize the **Parser** with our list of terminal **tokens**, our **grammar**
# rules, and the name of the root. Reverse the operators because Jison orders
# precedence from low to high, and we have it high to low
# (as in [Yacc](http://dinosaur.compilertools.net/yacc/index.html)).
exports.parser = new Parser
  tokens      : tokens.join ' '
  bnf         : grammar
  operators   : operators.reverse()
  startSymbol : 'Root'
