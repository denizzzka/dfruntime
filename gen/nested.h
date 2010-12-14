#ifndef LDC_GEN_NESTED_H
#define LDC_GEN_NESTED_H

#include "declaration.h"
#include "mtype.h"
#include "gen/dvalue.h"
#include "gen/llvm.h"

///////////////////////////////////////////////////////////
// Nested variable and context helpers
///////////////////////////////////////////////////////////

/// Creates the context value for a nested function.
void DtoCreateNestedContext(FuncDeclaration* fd);

/// Allocate space for variable accessed from nested function.
void DtoNestedInit(VarDeclaration* vd);

/// Resolves the nested context for classes and structs with arbitrary nesting.
#if DMDV2
LLValue* DtoResolveNestedContext(Loc loc, AggregateDeclaration *decl, LLValue *value);
#else
LLValue* DtoResolveNestedContext(Loc loc, ClassDeclaration *decl, LLValue *value);
#endif

/// Gets the context value for a call to a nested function or creating a nested
/// class or struct with arbitrary nesting.
llvm::Value* DtoNestedContext(Loc loc, Dsymbol* sym);

/// Gets the DValue of a nested variable with arbitrary nesting.
DValue* DtoNestedVariable(Loc loc, Type* astype, VarDeclaration* vd, bool byref = false);

#endif
