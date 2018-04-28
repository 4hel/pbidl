/*
* Copyright (C) 2018 YY Inc. All rights reserved.
*
* Licensed under the Apache License, Version 2.0 (the "License"); 
* you may not use this file except in compliance with the License. 
* You may obtain a copy of the License at
*
*	http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, 
* software distributed under the License is distributed on an "AS IS" BASIS, 
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. 
* See the License for the specific language governing permissions and 
* limitations under the License.
*/

%{

package main

import (
	"fmt"
	"os"
    "flag"
    "io/ioutil"
    "strconv"
    "regexp"
)

// 数据类型
const (
    TYPE_INT32  = 1
    TYPE_INT64  = 2
    TYPE_DOUBLE  = 3
    TYPE_STRING = 4
    TYPE_BOOL = 5
    TYPE_FLOAT  = 6
    TYPE_IMPORT = 100
    TYPE_ID = 101
    TYPE_LIST  = 102
    TYPE_MAP = 103
)

// 枚举定义
type enumItem struct {
    name    string
    value   int64
}

type enumInfo struct {
    name    string
    items   []enumItem
}

// 类型定义
type typeDef struct {
    ttype   int
    tname   string
    tlist   *typeDef
    tmap1   *typeDef
    tmap2   *typeDef
}

// message定义
type msgItem struct {
    ttype   typeDef
    name    string
    index   int64
}

type msgInfo struct {
    name    string
    items   []msgItem
}

var (
    mReDigit    *regexp.Regexp  // 数字的正则
    mReId       *regexp.Regexp  // 变量的正则
    mReNs       *regexp.Regexp  // a.b.c.d这种类型的正则
    mRePath     *regexp.Regexp  // 路径的正则
)

var (
    mPkg    string
    mEnums  []enumInfo
    mTMsg   string          // 第一个msg，认为是顶层msg
    mMsgs   = make(map[string]msgInfo, 50)
    mImports []string
    mOpts   = make(map[string]string,10)
)

%}

%union{
    Line    int
	Int     int64
    String  string
    Type    *typeDef
    Enum    []enumItem
    Msg     []msgItem
}

%token PACKAGE IMPORT OPTION ENUM MESSAGE SYNTAX ID NS PATH STRING NUMBER TINT32 TINT64 TDOUBLE TFLOAT TSTRING TBOOL TLIST TMAP REPEATED OPTIONAL TRUE FALSE RESERVED TO

%%
mp          :   syntax package import_opts body
            |   syntax package body
            ;

syntax      :
            |   SYNTAX '=' STRING ';'
            ;


package     :   PACKAGE ID ';' {
                mPkg = $2.String
            }
            |   PACKAGE NS ';' {
                mPkg = $2.String
            }
            ;

import_opts :   import_opt
            |   import_opt import_opts
            ;

import_opt  :   import
            |   option
            ;

import      :   IMPORT STRING ';' {
                mImports = append(mImports, $2.String)
            }
            ;

option      :   OPTION ID '=' STRING ';' {
                mOpts[$2.String] = $4.String
            }
            |    OPTION ID '=' TRUE ';'
            |    OPTION ID '=' FALSE ';'
            ;

body        :   defs
            |   defs body
            ;

defs        :   enum
            |   message
            ;

enum        :   ENUM ID '{' enumbody '}' {
                mEnums = append(mEnums, enumInfo{name:$2.String, items:$4.Enum})
            }
            ;

enumbody    :
            |   enumlines {
                $$.Enum = $1.Enum
            }
            ;

enumlines   :   enumline {
                $$.Enum = $1.Enum
            }
            |   enumline enumlines {
                $$.Enum = append($1.Enum, $2.Enum...)
            }
            ;

enumline    :   ID '=' NUMBER ';' {
                $$.Enum = []enumItem{enumItem{name:$1.String, value:$3.Int}}
            }
            ;

message     :   MESSAGE ID '{' messagebody '}' {
                if len(mTMsg)==0 {
                    mTMsg = $2.String
                }
                mMsgs[$2.String] = msgInfo{name:$2.String, items:$4.Msg}
            }
            ;

messagebody :
            |   messagelines {
                $$.Msg = $1.Msg
            }
            ;

messagelines:   messageline {
                $$.Msg = $1.Msg
            }
            |   messageline messagelines{
                $$.Msg = append($1.Msg, $2.Msg...)
            }
            ;

messageline :   modifier types ID '=' NUMBER ';' {
                $$.Msg = []msgItem{msgItem{ttype:*$2.Type, name:$3.String, index:$5.Int}}
            }
            |   RESERVED idlist ';'
            ;

modifier    :
            |   OPTIONAL
            |   REPEATED
            ;

// TINT32 TINT64 TDOUBLE TSTRING TLIST TMAP
types       :   basetype {
                $$.Type = $1.Type
            }
            |   NS {
                $$.Type = &typeDef{ttype:TYPE_IMPORT, tname:$1.String}
            }
            |   complextype {
                $$.Type = $1.Type
            }
            ;

basetype    :   TINT32 {
                $$.Type = &typeDef{ttype:TYPE_INT32}
            }
            |   TINT64 {
                $$.Type = &typeDef{ttype:TYPE_INT64}
            }
            |   TDOUBLE {
                $$.Type = &typeDef{ttype:TYPE_DOUBLE}
            }
            |   TSTRING {
                $$.Type = &typeDef{ttype:TYPE_STRING}
            }
            |   TBOOL {
                $$.Type = &typeDef{ttype:TYPE_BOOL}
            }
            |   TFLOAT {
                $$.Type = &typeDef{ttype:TYPE_FLOAT}
            }
            |   ID {
                $$.Type = &typeDef{ttype:TYPE_ID, tname:$1.String}
            }
            ;

complextype :   TLIST '<' types '>' {
                $$.Type = &typeDef{ttype:TYPE_LIST, tlist:$3.Type}
            }
            |   TMAP '<' basetype ',' types '>' {
                $$.Type = &typeDef{ttype:TYPE_MAP, tmap1:$3.Type, tmap2:$5.Type}
            }
            ;


idlist      :   idpart
            |   idpart ',' idlist
            ;


idpart      :   NUMBER
            |   NUMBER TO NUMBER
            ;
%%

type PbLex struct {
	s string
	pos int
    line int
}

// line表示是否处于行注释内部
func (l *PbLex)skipComment(line bool) {
    if line {
        for l.pos<len(l.s) && l.s[l.pos]!='\n' {
            l.pos++
        }
        if l.pos<len(l.s) {
            l.line++
            l.pos++
        }
        return
    } else {
        for l.pos<len(l.s) {
            if l.s[l.pos]=='\n' {
                l.line++
            } else if l.s[l.pos]=='*' {
                if l.pos+1<len(l.s) && l.s[l.pos+1]=='/' {
                    l.pos += 2
                    break
                }
            }
            l.pos++
        }
        return
    }
}

// 词法分析
func (l *PbLex) Lex(lval *PbSymType) int {
    defer func() {
        lval.Line = l.line
    }()
start:
    for l.pos<len(l.s) && (l.s[l.pos]==' ' || l.s[l.pos]=='\t') { // 跳过空格
		l.pos += 1
	}

    if l.pos+2<=len(l.s) && l.s[l.pos]=='/'{ // 处理注释
        if l.s[l.pos+1] == '/' {
            l.pos += 2
            l.skipComment(true)
            goto start
        } else if l.s[l.pos+1] == '*' {
            l.pos += 2
            l.skipComment(false)
            goto start
        }
    }
    if l.pos>=len(l.s) {
        fmt.Printf("parse done\n")
        return 0
    } else if l.s[l.pos]=='"' {
        l.pos++
        idx := l.pos
        for l.pos<len(l.s) {
            if l.s[l.pos]=='\\' {
                l.pos++
            } else if l.s[l.pos]=='"' {
                lval.String = l.s[idx:l.pos]
                l.pos++
                return STRING
            }
            l.pos++
        }
        l.Error("不匹配的双引号")
    }

    switch l.s[l.pos] {
    case '{':fallthrough
    case '}':fallthrough
    case '=':fallthrough
    case ';':fallthrough
    case '.':fallthrough
    case ',':fallthrough
    case '<':fallthrough
    case '>':
        lval.String = l.s[l.pos:l.pos+1]
        l.pos++
        return int(l.s[l.pos-1])
    case '\r':
        l.pos++
        goto start
    case '\n':
        l.pos++
        l.line++
        goto start
    }

    idx := l.pos
    if l.s[idx]>='1' && l.s[idx]<='9' { // 不支持八进制
        d := mReDigit.FindString(l.s[idx:])
        lval.Int,_ = strconv.ParseInt(d, 10, 32)
        l.pos += len(d)
        //fmt.Printf("return int %v\n", lval.Int)
        return NUMBER
    } else if (l.s[idx]>='a' && l.s[idx]<='z') || (l.s[idx]>='A' && l.s[idx]<='Z') { // 不允许_开头
        if d := mRePath.FindString(l.s[idx:]); len(d)>0 {
            lval.String = d
            l.pos += len(d)
            //fmt.Printf("return path %v\n", lval.String)
            return PATH
        } else if d := mReNs.FindString(l.s[idx:]); len(d)>0 {
            lval.String = d
            l.pos += len(d)
            //fmt.Printf("return NS %v\n", lval.String)
            return NS
        } else {
            d := mReId.FindString(l.s[idx:])
            lval.String = d
            l.pos += len(d)
            //fmt.Printf("return id %v\n", lval.String)
        }
    } else if l.s[idx]=='0' {
        lval.Int = 0
        l.pos++
        return NUMBER
    } else {
        fmt.Printf("unknow id %v\n", l.s[idx])
        l.pos++
        return int(l.s[idx])
    }

    // PACKAGE OPTION ENUM MESSAGE SYNTAX ID NS PATH STRING NUMBER TINT32 TINT64 TDOUBLE TSTRING TBOOL TLIST TMAP
    switch lval.String {
    case "package":return PACKAGE
    case "import":return IMPORT
    case "option":return OPTION
    case "enum":return ENUM
    case "message":return MESSAGE
    case "syntax":return SYNTAX
    case "int32":return TINT32
    case "int64":return TINT64
    case "double":return TDOUBLE
    case "float":return TFLOAT
    case "string":return TSTRING
    case "bool":return TBOOL
    case "list":return TLIST
    case "map":return TMAP
    case "repeated":return REPEATED
    case "optional":return OPTIONAL
    case "true":return TRUE
    case "false":return FALSE
    case "reserved":return RESERVED
    case "to":return TO
    }
    //fmt.Printf("return id %v\n", lval.String)
    return ID
}

func (l *PbLex) Error(s string) {
    if l.pos>=len(l.s) {
        fmt.Printf("syntax error line %v. end: %s\n", l.line, s)
    } else {
        left := len(l.s)-l.pos
        if left > 24 {
            left = 24
        }
        fmt.Printf("%v line %v: [%s], %s\n", os.Args[1], l.line, l.s[l.pos:l.pos+left], s)
    }
}

func usage(info string) {
    fmt.Fprintf(os.Stderr, "%s\n", info)
}

func main() {
    flag.Parse()
    inputs := flag.Args()
    if len(inputs) != 1 {
        usage("no input file")
        return
    }
    input := inputs[0]

    file, err := os.Open(input)
    if err != nil {
        fmt.Println("open file %s error:%v", input, err)
        return
    }

    data,_ := ioutil.ReadAll(file)
    file.Close()

    mReDigit, _ = regexp.Compile(`^\d+`)
    mReId, _    = regexp.Compile(`^\w+`)
    mReNs, _    = regexp.Compile(`^\w+(\.[a-zA-Z][\w]*)+`)
    mRePath,_   = regexp.Compile(`^\w+(/[\w]+)+`)

    PbParse(&PbLex{s: string(data), line:1})

    fmt.Printf("enum:%v\n", mEnums)
    fmt.Printf("msg:%v\n", mMsgs)
    fmt.Printf("pkg:%v\n", mPkg)
    fmt.Printf("opts:%v\n", mOpts)
    fmt.Printf("imports:%v\n", mImports)
}
