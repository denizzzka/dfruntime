/**
 * Compiler implementation of the
 * $(LINK2 http://www.dlang.org, D programming language).
 *
 * Template implementation.
 *
 * Copyright:   Copyright (c) 1999-2017 by Digital Mars, All Rights Reserved
 * Authors:     $(LINK2 http://www.digitalmars.com, Walter Bright)
 * License:     $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Source:      $(LINK2 https://github.com/dlang/dmd/blob/master/src/ddmd/templateparamsem.d, _templateparamsem.d)
 */

module ddmd.templateparamsem;

// Online documentation: https://dlang.org/phobos/ddmd_templateparamsem.html

import ddmd.arraytypes;
import ddmd.dsymbol;
import ddmd.dscope;
import ddmd.dtemplate;
import ddmd.globals;
import ddmd.expression;
import ddmd.root.rootobject;
import ddmd.semantic;
import ddmd.mtype;
import ddmd.visitor;

/************************************************
 * Performs semantic on TemplateParameter AST nodes.
 *
 * Params:
 *      tp = element of `parameters` to be semantically analyzed
 *      sc = context
 *      parameters = array of `TemplateParameters` supplied to the `TemplateDeclaration`
 * Returns:
 *      `true` if no errors
 */
extern(C++) bool tpsemantic(TemplateParameter tp, Scope* sc, TemplateParameters* parameters)
{
    scope v = new TemplateParameterSemanticVisitor(sc, parameters);
    tp.accept(v);
    return v.result;
}


private extern (C++) final class TemplateParameterSemanticVisitor : Visitor
{
    alias visit = super.visit;

    Scope* sc;
    TemplateParameters* parameters;
    bool result;

    this(Scope* sc, TemplateParameters* parameters)
    {
        this.sc = sc;
        this.parameters = parameters;
    }

    override void visit(TemplateTypeParameter ttp)
    {
        //printf("TemplateTypeParameter.semantic('%s')\n", ident.toChars());
        if (ttp.specType && !reliesOnTident(ttp.specType, parameters))
        {
            ttp.specType = ttp.specType.semantic(ttp.loc, sc);
        }
        version (none)
        {
            // Don't do semantic() until instantiation
            if (ttp.defaultType)
            {
                ttp.defaultType = ttp.defaultType.semantic(ttp.loc, sc);
            }
        }
        result = !(ttp.specType && isError(ttp.specType));
    }

    override void visit(TemplateValueParameter tvp)
    {
        tvp.valType = tvp.valType.semantic(tvp.loc, sc);
        version (none)
        {
            // defer semantic analysis to arg match
            if (tvp.specValue)
            {
                Expression e = tvp.specValue;
                sc = sc.startCTFE();
                e = e.semantic(sc);
                sc = sc.endCTFE();
                e = e.implicitCastTo(sc, tvp.valType);
                e = e.ctfeInterpret();
                if (e.op == TOKint64 || e.op == TOKfloat64 ||
                    e.op == TOKcomplex80 || e.op == TOKnull || e.op == TOKstring)
                    tvp.specValue = e;
            }

            if (tvp.defaultValue)
            {
                Expression e = defaultValue;
                sc = sc.startCTFE();
                e = e.semantic(sc);
                sc = sc.endCTFE();
                e = e.implicitCastTo(sc, tvp.valType);
                e = e.ctfeInterpret();
                if (e.op == TOKint64)
                    tvp.defaultValue = e;
            }
        }
        result = !isError(tvp.valType);
    }

    override void visit(TemplateAliasParameter tap)
    {
        if (tap.specType && !reliesOnTident(tap.specType, parameters))
        {
            tap.specType = tap.specType.semantic(tap.loc, sc);
        }
        tap.specAlias = aliasParameterSemantic(tap.loc, sc, tap.specAlias, parameters);
        version (none)
        {
            // Don't do semantic() until instantiation
            if (tap.defaultAlias)
                tap.defaultAlias = tap.defaultAlias.semantic(tap.loc, sc);
        }
        result = !(tap.specType && isError(tap.specType)) && !(tap.specAlias && isError(tap.specAlias));
    }

    override void visit(TemplateTupleParameter ttp)
    {
        result = true;
    }
}

/***********************************************
 * Support function for performing semantic analysis on `TemplateAliasParameter`.
 *
 * Params:
 *      loc = location (for error messages)
 *      sc = context
 *      o = object to run semantic() on, the `TemplateAliasParameter`s `specAlias` or `defaultAlias`
 *      parameters = array of `TemplateParameters` supplied to the `TemplateDeclaration`
 * Returns:
 *      object resulting from running `semantic` on `o`
 */
RootObject aliasParameterSemantic(Loc loc, Scope* sc, RootObject o, TemplateParameters* parameters)
{
    if (o)
    {
        Expression ea = isExpression(o);
        Type ta = isType(o);
        if (ta && (!parameters || !reliesOnTident(ta, parameters)))
        {
            Dsymbol s = ta.toDsymbol(sc);
            if (s)
                o = s;
            else
                o = ta.semantic(loc, sc);
        }
        else if (ea)
        {
            sc = sc.startCTFE();
            ea = ea.semantic(sc);
            sc = sc.endCTFE();
            o = ea.ctfeInterpret();
        }
    }
    return o;
}
