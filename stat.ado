program stat, rclass 
version 12.1
syntax varlist [if] [in] [aweight fweight pweight] [, Detail by(varname) Statistics(str)  missing seps(numlist) /*
*/     CASEwise Columns(str) Format Format2(str) /*
*/      LAbelwidth(int -1) VArwidth(int -1) LOngstub Missing /*
*/      SAME SAVE noSEParator noTotal septable(string)]

noi di "`statistics'"

if ("`weight'"!="") local wt [`weight'`exp']

if "`stats'" ~= ""{
    local statistics `stats'
}




if "`statistics'" == ""{		
    if "`detail'" == ""{
        local statistics  n mean sd min max
    }
    else{
        local statistics n mean sd skewness kurtosis min p1 p5 p10 p25 p50 p50 p75 p90 p95 p99 max
        local seps 5 11
    }
}    

if "`casewise'" != "" {
    local same same
}

if `"`stats'"' != "" {
    if `"`statistics'"' != "" {
        di as err /*
        */ "may not specify both statistics() and stats() options"
        exit 198
    }
    local statistics `"`stats'"'
    local stats
}

if "`nototal'" != "" & "`by'" == "" {
    di as txt "nothing to display"
    exit 0
}

if "`format'" != "" & `"`format2'"' != "" {
    di as err "may not specify both format and format()"
    exit 198
}
if `"`format2'"' != "" {
    capt local tmp : display `format2' 1
    if _rc {
        di as err `"invalid %fmt in format(): `format2'"'
        exit 120
    }
}

if `"`columns'"' == "" {
    local incol "variables"
}
else if `"`columns'"' == substr("variables",1,length(`"`columns'"')) {
    local incol "variables"
}
else if `"`columns'"' == substr("statistics",1,length(`"`columns'"')) {
    local incol "statistics"
}
else if `"`columns'"' == "stats" {
    local incol "statistics"
}
else {
    di as err `"column(`columns') invalid -- specify "' /*
    */ "column(variables) or column(statistics)"
    exit 198
}

if "`longstub'" != "" | "`by'" == "" | `varwidth' != -1 {
    local descr descr
}

if `varwidth' == -1 {
    local varwidth 12
}
else if !inrange(`varwidth',8,16) {
    local varwidth = clip(`varwidth',8,16)
    dis as txt ///
    "(option varwidth() outside valid range 8..16; `varwidth' assumed)"
}

if `labelwidth' == -1 {
    local labelwidth 16
}
else if !inrange(`labelwidth',8,32) {
    local labelwidth = clip(`labelwidth',8,32)
    dis as txt ///
    "(option labelwidth() outside valid range 8..32; `labelwidth' assumed)"
}

* sample selection

marksample touse, novar
if "`same'" != "" {
    markout `touse' `varlist'
}
if "`by'" != "" & "`missing'" == "" {
    markout `touse' `by' , strok
}
qui count if `touse'
local ntouse = r(N)
if `ntouse' == 0 {
    error 2000
}
if `"`weight'"' != "" {
    local wght `"[`weight'`exp']"'
}

// varlist -> var1, var2, ... variables
//            fmt1, fmt2, ... display formats

tokenize "`varlist'"
local nvars : word count `varlist'
forvalues i = 1/`nvars' {
    local var`i' ``i''
    if "`format'" != "" {
        local fmt`i' : format ``i''
    }
    else if `"`format2'"' != "" {
        local fmt`i' `format2'
    }
    else {
        local fmt`i' %9.0g
    }
}
if `nvars' == 1 & `"`columns'"' == "" {
    local incol statistics
}

* Statistics

Stats2 `statistics'
local stats   `r(names)'
local expr    `r(expr)'
local cmd    `r(cmd)'
local summopt `r(summopt)'
local pctileopt `r(pctileopt)'
local nstats : word count `stats'

tokenize `expr'
forvalues i = 1/`nstats' {
    local expr`i' ``i''
}
tokenize `cmd'
forvalues i = 1/`nstats' {
    local cmd`i' ``i''
}
tokenize `stats'
forvalues i = 1/`nstats' {
    local name`i' ``i''
    local names "`names' ``i''"
    if `i' < `nstats' {
        local names "`names',"
    }
}
if "`separator'" == "" & ( (`nstats' > 1 & "`incol'" == "variables") /*
    */         |(`nvars' > 1  & "`incol'" == "statistics")) {
    local sepline yes
}

local matsize : set matsize
local matreq = max(`nstats',`nvars')
if `matsize' < `matreq' {
    di as err /*
    */ "set matsize to at least `matreq' (see help matsize for details)"
    exit 908
}

* compute the statistics
* ----------------------

if "`by'" != "" {
    * conditional statistics are saved in matrices Stat1, Stat2, etc

    * the data are sorted on by groups, putting unused obs last
    * be careful not to change the sort order
    * note that touse is coded -1/0 rather than 1/0!

    sort `touse' `by'

    /* code from binscatter */
    qui count if `touse'
    local samplesize=r(N)
    local touse_first=_N-`samplesize'+1
    local touse_last=_N
    local bytype : type `by'
    mata: characterize_unique_vals_sorted("`by'",`touse_first',`touse_last', 100)
    local nby = r(r)
    tempname by_boundaries by_values
    matrix `by_boundaries'=r(boundaries)        
    matrix `by_values'=r(values)

    /* get back to original */
    forvalues iby = 1/`nby' {
        tempname Stat`iby'
        mat `Stat`iby'' = J(`nstats',`nvars',0)
        mat colnames `Stat`iby'' = `varlist'
        mat rownames `Stat`iby'' = `stats'
        local byval  `=`by_values'[`iby', 1]'
        local by1 `=`by_boundaries'[`iby',1]'
        local by2 `=`by_boundaries'[`iby',2]' 

        * loop over all variables
        forvalues i = 1/`nvars' {
            if regexm("`cmd'", "sum") {
                qui summ `var`i'' in `by1'/`by2' `wght', `summopt'
                forvalues is = 1/`nstats' {
                    if "`cmd`is''" == "sum"{
                        if "`name`is''"== "freq"{
                            mat `Stat`iby''[`is',`i'] = `by2' - `by1' +1
                        }
                        else if  "`name`is''"== "nmissing"{
                            mat `Stat`iby''[`is',`i'] = `by2' - `by1' + 1 - `expr`is''
                        }
                        else{
                            mat `Stat`iby''[`is',`i'] = `expr`is''
                        }
                    }
                }
            }
            if "`pctileopt'" ~= ""{
                qui _pctile `var`i'' in `by1'/`by2' `wght', p(`pctileopt')
                forvalues is = 1/`nstats' {
                    if "`cmd`is''" == "pctile"{
                        mat `Stat`iby''[`is',`i'] = `expr`is''
                    }
                }
            }
        }   




        * save label for groups in lab1, lab2 etc
        if substr("`bytype'",1,3) != "str" {
            local lab`iby' : label (`by') `byval'
        }
        else {
            /* 32 = max value of `labelwidth'               */
            /* We record c(maxvallablen) because of r()     */
            /* We use -display- to expand char(0) to \0     */
            local lab`iby' : di (substr(`byval', 1, c(maxvlabellen)))
        }
    }
}
else {
    local nby 0
}

if "`nototal'" == "" {
    * unconditional (Total) statistics are stored in Stat`nby+1'
    local iby = `nby'+1

    tempname Stat`iby'
    mat `Stat`iby'' = J(`nstats',`nvars',0)
    mat colnames `Stat`iby'' = `varlist'
    mat rownames `Stat`iby'' = `stats'

    forvalues i = 1/`nvars' {
        if regexm("`cmd'", "sum") {
            qui summ `var`i''  `wght' if `touse' == 1, `summopt'
            forvalues is = 1/`nstats' {
                if "`cmd`is''" == "sum"{
                    if "`name`is''"== "freq"{
                        mat `Stat`iby''[`is',`i'] = _N
                    }
                    else if  "`name`is''"== "nmissing"{
                        mat `Stat`iby''[`is',`i'] = _N - `expr`is''
                    }
                    else{
                        mat `Stat`iby''[`is',`i'] = `expr`is''
                    }
                }
            }
        }
        if "`pctileopt'" ~= ""{
            qui _pctile `var`i'' `wght' if `touse' == 1, p(`pctileopt')
            forvalues is = 1/`nstats' {
                if "`cmd`is''" == "pctile"{
                    mat `Stat`iby''[`is',`i'] = `expr`is''
                }
            }
        }
    }
    local lab`iby' "Total"
}


* constants for displaying results
* --------------------------------

if "`by'" != "" {
    if substr("`bytype'",1,3) != "str" {
        local lv : value label `by'
        if "`lv'" != "" {
            local lg : label (`by') maxlength
            local byw = min(`labelwidth',`lg')
        }
        else {
            /* okay for strLs */
            local byw 8
        }
    }
    else {
        local byw=min(real(substr("`bytype'",4,.)),`labelwidth')
        local bytype str
    }
    capture local for : format `by'
    capture local if_date_for = substr("`for'", index("`for'", "%"), index("`for'", "d"))
    capture local if_time_for = substr("`for'", index("`for'", "%"), index("`for'", "t"))
    if "`if_date_for'" == "%d" | "`if_time_for'" == "%t" {
        if "`if_date_for'" == "%d" {
            local has_M = index("`for'", "M")
            local has_L = index("`for'", "L")
            if `has_M' > 0 | `has_L' > 0 {
                local byw = 18
            }
            else {
                local byw = 11
            }
        }
        else {
            local byw = 9
        }
    }
    else {
        local byw = max(length("`by'"), `byw')
    }
    if "`nototal'" == "" {
        local byw = max(`byw', 6)
    }
}
else {
    local byw 8
}

* number of chars in display format
local ndigit  9
local colwidth = `ndigit'+1

if "`incol'" == "statistics" {
    local lleft = (1 + `byw')*("`by'"!="") + ///
    (`varwidth'+1)*("`descr'"!="")
}
else {
    local lleft = (1 + `byw')*("`by'"!="") + (8+1)*("`descr'"!="")
}
local cbar  = `lleft' + 1

local lsize = c(linesize)
* number of non-label elements in the row of a block
local neblock = int((`lsize' - `cbar')/10)
if "`seps'" == ""{
    * number of blocks if stats horizontal
    local nsblock  = 1 + int((`nstats'-1)/`neblock')
    * number of blocks if variables horizontal
    local is20  0 
    forvalues i = 1/`nsblock' {
        local is1`i' `=`is2`=`i'-1''+1'
        local is2`i' `=min(`nstats', `i'+`neblock'-1)'
    }
    local nvblock  = 1 + int((`nvars'-1)/`neblock')
    local i20  0 
    forvalues i = 1/`nvblock' {
        local i1`i' `=`i2`=`i'-1''+1'
        local i2`i' `=`i1`i''+`neblock'-1'
    }
}
else{
    local seps `seps' `nstats'
    local nsblock : word count `seps'
    local is20  0 
    forvalues i = 1/`nsblock' {
        local is1`i' `=`is2`=`i'-1''+1'
        local is2`i' `: word `i' of `seps''
    }
    local nvblock : word count `seps'
    local i20  0 
    forvalues i = 1/`nsblock' {
        local i1`i' `=`i2`=`i'-1''+1'
        local i2`i' `: word `i' of `seps''
    }
}


if "`descr'" != "" & "`by'" != "" {
    local byalign lalign
}
else {
    local byalign ralign
}

* display results
* ---------------

if "`incol'" == "statistics" {

    * display the results: horizontal = statistics (block wise)
    /*         
    if "`descr'" == "" {
        di as txt _n `"Summary for variables: `varlist'"'
        if "`by'" != "" {
            local bylabel : var label `by'
            if `"`bylabel'"' != "" {
                local bylabel `"(`bylabel')"'
            }
            di as txt _col(6) `"by categories of: `by' `bylabel'"'
        }
    }
    */
    di

    * loop over all nsblock blocks of statistics

    forvalues isblock = 1/`nsblock' {

        * is1..is2 are indices of statistics in a block
        local is1 = `is1`isblock''
        local is2 = `is2`isblock''

        * display header
        if "`by'" != "" {
            local byname = abbrev("`by'",`byw')
        di as txt "{`byalign' `byw':`byname'} {...}"
        }
        if "`descr'" != "" {
        di as txt "{ralign `varwidth':variable} {...}"
        }
    di as txt "{c |}" _c
        forvalues is = `is1'/`is2' {
            di as txt %`colwidth's "`name`is''" _c
        }
        local ndash = `colwidth'*(`is2'-`is1'+1)
    di as txt _n "{hline `lleft'}{c +}{hline `ndash'}"

        * loop over the categories of -by- (1..nby) and -total- (nby+1)
        local nbyt = `nby' + ("`nototal'" == "")
        forvalues iby = 1/`nbyt'{
            forvalues i = 1/`nvars' {
                if "`by'" != "" {
                    if `i' == 1 {
                        local lab = substr(`"`lab`iby''"', 1,`byw')
                        if `"`lab'"' != "Total" {
                            capture local val_lab : value label `by'
                            if "`val_lab'" == "" {
                                local type : type `by'
                                local yes_str = index("`type'", "str")
                                if `yes_str' == 0 {
                                    capture local for : format `by'
                                    capture local if_date_for = index("`for'", "%d")
                                    capture local if_time_for = index("`for'", "%t")
                                    if `if_date_for' > 0 | `if_time_for' > 0 {
                                        local date_for : display `for' `lab'
                                    di in txt `"{`byalign' `byw':`date_for'} {...}"'
                                    }
                                    else {
                                        /* okay for strLs */
                                    di in txt `"{`byalign' `byw':`lab'} {...}"'
                                    }

                                }
                                else {
                                di in txt `"{`byalign' `byw':`lab'} {...}"'
                                }
                            }
                            else {
                            di in txt `"{`byalign' `byw':`lab'} {...}"'
                            }

                        }
                        else {
                        di in txt `"{`byalign' `byw':`lab'} {...}"'
                        }
                    }
                    else {
                    di "{space `byw'} {...}"
                    }
                }
                if "`descr'" != "" {
                    local avn = abbrev("`var`i''",`varwidth')
                di as txt "{ralign `varwidth':`avn'} {...}"
                }
            di as txt "{c |}{...}"
                forvalues is = `is1'/`is2' {
                    local s : display `fmt`i'' `Stat`iby''[`is',`i']
                    di as res %`colwidth's "`s'" _c
                }
                di
            }
            if (`iby' >= `nbyt') {
            di as txt "{hline `lleft'}{c BT}{hline `ndash'}"
            }
            else if ("`sepline'" != "") | ((`iby'+1 == `nbyt') & ("`nototal'" == "")) {
            di as txt "{hline `lleft'}{c +}{hline `ndash'}"
            }
        }

        if `isblock' < `nsblock' {
            display
        }
    } /* isblock */
}
else {
    * display the results: horizontal = variables (block wise)

    if "`descr'" == "" {
        di as txt _n `"Summary statistics:`names'"'
        if "`by'" != "" {
            local bylabel : var label `by'
            if `"`bylabel'"' != "" {
                local bylabel `"(`bylabel')"'
            }
            di as txt `"  by categories of: `by' `bylabel'"'
        }
    }
    di

    * loop over all nvblock blocks of variables

    local i2 0
    forvalues iblock = 1/`nvblock' {

        * i1..i2 are indices of variables in a block
        local i1 = `i1`iblock''
        local i2 = `i2`iblock''

        * display header
        if "`by'" != "" {
        di as txt "{`byalign' `byw':`by'} {...}"
        }
        if "`descr'" != "" {
        di as txt "   stats {...}"
        }
    di as txt "{c |}{...}"
        forvalues i = `i1'/`i2' {
            * here vars are abbreviated to 8 chars
            di as txt %`colwidth's abbrev("`var`i''",8) _c
        }
        local ndash = (`ndigit'+1)*(`i2'-`i1'+1)
    di as txt _n "{hline `lleft'}{c +}{hline `ndash'}"

        * loop over the categories of -by- (1..nby) and -total- (nby+1)
        local nbyt = `nby' + ("`nototal'" == "")
        forvalues iby = 1/`nbyt'{
            forvalues is = 1/`nstats' {
                if "`by'" != "" {
                    if `is' == 1 {
                        local lab = substr(`"`lab`iby''"', 1, `byw')
                    di as txt `"{`byalign' `byw':`lab'} {...}"'
                    }
                    else {
                    di as txt "{space `byw'} {...}"
                    }
                }
                if "`descr'" != "" {
                    * names of statistics are at most 8 chars
                di as txt `"{ralign 8:`name`is''} {...}"'
                }
            di as txt "{c |}{...}"
                forvalues i = `i1'/`i2' {
                    local s : display `fmt`i'' `Stat`iby''[`is',`i']
                    di as res %`colwidth's "`s'" _c
                }
                di
            }
            if (`iby' >= `nbyt') {
            di as txt "{hline `lleft'}{c BT}{hline `ndash'}"
            }
            else if ("`sepline'" != "") | ((`iby'+1 == `nbyt') & ("`nototal'" == "")) {
            di as txt "{hline `lleft'}{c +}{hline `ndash'}"
            }
        } /* forvalues iby */

        if `iblock' < `nvblock' {
            display
        }
    } /* forvalues iblock */
}

* save results (mainly for certification)
* ---------------------------------------


if "`by'" == ""{
    local iby `=`nby' + 1'
    foreach is of numlist 1/`nstats'{
        local localname  "`name`is''"
        return scalar `localname' = `=`Stat`iby''[`is',1]'
    }
}
forvalues iby = 1/`nby' {
    local bylist `bylist' `=`by_values'[`iby',1]'
    foreach is of numlist 1/`nstats'{
        local localname  "`name`is''_`=`by_values'[`iby',1]'"
        return scalar `localname' = `=`Stat`iby''[`is',1]'
    }
}
return local statlist `stats'
return local bylist `bylist'

if "`output'" ~= ""{
    tempname memhold

    /* 
    *long 
    postfile `memhold' `by' str20 varname str5 statname value using `output', `replace'
    forvalues iby = 1/`nby' {
        forvalues ivar = 1/`nvars'{
            forvalues is = 1/`nstats'{
                post  `memhold' (`=`by_values'[`iby',1]') ("`var`ivar''") ("`name`is''") (`=`Stat`iby''[`is',`ivar']')
            }
        }
    }
    */

    *wide
    local varnames
    if `nstats' == 1{
        forvalues ivar = 1/`nvars'{
            local varnames `varnames' `var`ivar''
        }
    }
    else{
        forvalues is = 1/`nstats'{
            forvalues ivar = 1/`nvars'{
                local varnames `varnames' `var`ivar''_`name`is''
            }
        }

        postfile `memhold' `by' `varnames' using `output', `replace'
        forvalues iby = 1/`nby' {
            local post ""
            forvalues ivar = 1/`nvars'{
                forvalues is = 1/`nstats'{
                    local post  `post' (`=`Stat`iby''[`is',`ivar']')
                }
                post  `memhold' (`=`by_values'[`iby',1]') `post'
            }
        }
    }
    postclose `memhold'
}


end

/***************************************************************************************************
Modified helper function from tabstat

/* Stats str
processes the contents() option. It returns in
r(names)   -- names of statistics, separated by blanks
r(expr)    -- r() expressions for statistics, separated by blanks
r(summopt) -- option for summarize command (meanonly, detail)
***************************************************************************************************/


note: if you add statistics, ensure that the name of the statistic
is at most 8 chars long.
*/
cap program drop Stats2
program define Stats2, rclass
    if `"`0'"' == "" {
        local opt "mean"
    }
    else {
        local opt `"`0'"'
    }

    * ensure that order of requested statistics is preserved
    * invoke syntax for each word in input
    local class 0
    local nq 0
    foreach st of local opt {
        local 0 = lower(`", `st'"')

        capt syntax [, n freq nmissing MEan sd Variance SUm COunt MIn MAx Range SKewness Kurtosis /*
        */  SDMean SEMean p1 p5 p10 p25 p50 p75 p90 p95 p99 iqr q MEDian CV *]
        if _rc {
            di in err `"unknown statistic: `st'"'
            exit 198
        }

        if "`median'" != "" {
            local p50 p50
        }
        * class 1 : available via -summarize, meanonly-

        * summarize.r(N) returns #obs (note capitalization)
        if "`n'" != "" {
            local n N
        }
        local s "`n'`min'`mean'`max'`sum'"
        if "`s'" != "" {
            local names "`names' `s'"
            local expr  "`expr' r(`s')"
            local class = max(`class',1)
            local cmd "`cmd' sum"
            continue
        }
        if "`range'" != "" {
            local names "`names' range"
            local expr  "`expr' r(max)-r(min)"
            local class = max(`class',1)
            local cmd "`cmd' sum"
            continue
        }

        if "`freq'" != "" {
            local names "`names' freq"
            local expr  "`expr' r(N)"
            local class = max(`class',1)
            local cmd "`cmd' sum"
            continue
        }

        if "`nmissing'" != "" {
            local names "`names' nmissing"
            local expr  "`expr' r(N)"
            local class = max(`class',1)
            local cmd "`cmd' sum"
            continue
        }


        * class 2 : available via -summarize-

        if "`sd'" != "" {
            local names "`names' sd"
            local expr  "`expr' r(sd)"
            local class = max(`class',2)
            local cmd "`cmd' sum"
            continue
        }
        if "`sdmean'" != "" | "`semean'"!="" {
            local names "`names' se(mean)"
            local expr  "`expr' r(sd)/sqrt(r(N))"
            local class = max(`class',2)
            local cmd "`cmd' sum"
            continue
        }
        if "`variance'" != "" {
            local names "`names' variance"
            local expr  "`expr' r(Var)"
            local class = max(`class',2)
            local cmd "`cmd' sum"
            continue
        }
        if "`cv'" != "" {
            local names "`names' cv"
            local expr  "`expr' (r(sd)/r(mean))"
            local class = max(`class',2)
            local cmd "`cmd' sum"
            continue
        }

        * class 3 : available via -detail-

        local s "`skewness'`kurtosis'`p1'`p5'`p10'`p25'`p50'`p75'`p90'`p95'`p99'"
        if "`s'" != "" {
            local names "`names' `s'"
            local expr  "`expr' r(`s')"
            local class = max(`class',3)
            local cmd "`cmd' sum"
            continue
        }
        if "`iqr'" != "" {
            local names "`names' iqr"
            local expr  "`expr' r(p75)-r(p25)"
            local class = max(`class',3)
            local cmd "`cmd' sum"
            continue
        }
        if "`q'" != "" {
            local names "`names' p25 p50 p75"
            local expr  "`expr' r(p25) r(p50) r(p75)"
            local class = max(`class',3)
            local cmd "`cmd' sum"
            continue
        }

        if regexm("`options'","p[0-9]*"){
            local quantile `=regexr("`options'", "p", "")'
            local nq = `nq' + 1
            local names "`names' `options'"
            local expr "`expr' r(r`nq')"
            local pctileopt "`pctileopt' `quantile'"
            local cmd "`cmd' pctile"
        }
    }




    if `class' == 1 {
        local summopt "meanonly"
    }
    else if `class' == 3 {
        local summopt "detail"
    }
    return local names `names'
    return local expr  `expr'
    return local cmd  `cmd'
    return local summopt `summopt'
    return local pctileopt  `pctileopt'
end


/***************************************************************************************************
Helper function from binscatter (no change)
***************************************************************************************************/
version 12.1
set matastrict on

mata:

    void characterize_unique_vals_sorted(string scalar var, real scalar first, real scalar last, real scalar maxuq) {
        // Inputs: a numeric variable, a starting & ending obs #, and a maximum number of unique values
        // Requires: the data to be sorted on the specified variable within the observation boundaries given
        //              (no check is made that this requirement is satisfied)
        // Returns: the number of unique values found
        //          the unique values found
        //          the observation boundaries of each unique value in the dataset


        // initialize returned results
        real scalar Nunique
        Nunique=0

        real matrix values
        values=J(maxuq,1,.)

        real matrix boundaries
        boundaries=J(maxuq,2,.)

        // initialize computations
        real scalar var_index
        var_index=st_varindex(var)

        real scalar curvalue
        real scalar prevvalue

        // perform computations
        real scalar obs
        for (obs=first; obs<=last; obs++) {
            curvalue=_st_data(obs,var_index)

            if (curvalue!=prevvalue) {
                Nunique++
                if (Nunique<=maxuq) {
                    prevvalue=curvalue
                    values[Nunique,1]=curvalue
                    boundaries[Nunique,1]=obs
                    if (Nunique>1) boundaries[Nunique-1,2]=obs-1
                }
                else {
                    exit(error(134))
                }

            }
        }
        boundaries[Nunique,2]=last

        // return results
        stata("return clear")

        st_numscalar("r(r)",Nunique)
        st_matrix("r(values)",values[1..Nunique,.])
        st_matrix("r(boundaries)",boundaries[1..Nunique,.])

    }

end
