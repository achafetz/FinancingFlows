**************************
**    Financial Flows	**
**        Graphs        **
**						**
**     Aaron Chafetz    **
**     USAID/E3/PLC     **
**   Last Updated 7/2   **
**************************

********************************************************************************
********************************************************************************
	
** INITIAL SETUP **

	clear
	set more off

*  must be run each time Stata is opened
	/* Choose the project path location to where you want the project parent 
	   folder to go on your machine. Make sure it ends with a forward slash */
	global projectpath "U:\Chief Economist Work\"
	cd "$projectpath"
	
* Run a macro to set up study folder
	* Name the file path below
	local pFolder FinancingFlows
	foreach dir in `pFolder' {
		confirmdir "`dir'"
		if `r(confirmdir)'==170 {
			mkdir "`dir'"
			display in yellow "Project directory named: `dir' created"
			}
		else disp as error "`dir' already exists, not created."
		cd "$projectpath\`dir'"
		}
	* end

* Run initially to set up folder structure
* Choose your folders to set up as the local macro `folders'
	local folders RawData StataOutput StataFigures ExcelOutput Documents
	foreach dir in `folders' {
		confirmdir "`dir'"
		if `r(confirmdir)'==170 {
				mkdir "`dir'"
				disp in yellow "`dir' successfully created."
			}
		else disp as error "`dir' already exists. Skipped to next folder."
	}
	*end
*Set up global file paths located within project path
	*these folders must exist in the parent folder
	global projectpath `c(pwd)'
	global data "$projectpath\RawData\"
	global output "$projectpath\StataOutput\"
	global graph "$projectpath\StataFigures\"
	global excel "$projectpath\ExcelOutput\"
	disp as error "If initial setup, move data to RawData folder."

********************************************************************************
********************************************************************************
	

*** FIGURE 1 ***

*Setup
	*availability sample
		use "$output\financialflows.dta", clear
		collapse (sum) oda oof remittances private, by(year)
		gen official = oda + oof
			lab var official "ODA and other offical flows"
		drop if year<1995 | year>2012
		keep year official remittances private
		tempfile availability
		save `availability'
	*constant sample
		use "$output\financialflows_const.dta", clear
		collapse (sum) epol_oda epol_oof epol_remittances epol_private, by(year)
		gen epol_official = epol_oda + epol_oof
			lab var epol_official "ODA and other offical flows"
			drop epol_oda epol_oof
		merge 1:1 year using `availability', nogen
		foreach v of varlist epol_remittances-official{
			replace `v' = `v'/1000 //convert to billions
			} 
		gen ends = 1 if inlist(year, 1995, 2012)
		gen labela = "Availability" if year==2012
		gen labelc = "Constant" if year==2012
		
	*shares
		gen totflow_c = epol_remittances + epol_private + epol_official
		gen totflow_a = remittances + private + official
		foreach f of varlist epol_remittances-epol_official{
			gen sh_`f' = (`f'/totflow_c)*100
			}
			*end
		foreach f of varlist remittances-official{
			gen sh_`f' = (`f'/totflow_a)*100
			}
			*end
	
*Graph
	*Panel A
	*establish locals for loop
		local flow1 official 
		local flow2 remittances
		local flow3 private
		local color1 "15 111 198" 
		local color2 "16 207 115" 
		local color3 "4 97 123"
		local title1 "Net Official (ODA + OOF)" 
		local title2 "Remittances" 
		local title3 "Net Private"
		local yscale1 ""
		local yscale2 off
		local yscale3 off
	*graphs
		forvalues i = 1/3{
			twoway line epol_`flow`i'' year, lcolor("`color`i''") lwidth(medthick) || ///
				scatter epol_`flow`i'' year if ends==1, msize(large) mcolor("`color`i''") || ///
				scatter epol_`flow`i'' year if ends==1 & `i'==3, msize(medlarge) ///
					mcolor("`color`i''") mlabel(labelc) mlabposition(6) mlabcolor(black) || ///
				line `flow`i'' year, lcolor("166 166 166") lwidth(medthick) || ///
				scatter `flow`i'' year if ends==1, msize(large) mcolor("166 166 166") || ///
				scatter `flow`i'' year if ends==1 & `i'==3, msize(large) ///
					mcolor("166 166 166") mlabel(labela) mlabposition(6) mlabcolor(black) ///
				legend(off) ///
				title("`title`i''", color(black)) ///
				ytitle("") xtitle("") ///
				xlabel(1995(5)2012, notick) xscale(noline) ///
				ylabel(, grid angle(0) notick) yscale(`yscale`i'' noline) ///
				name(`flow`i'', replace) ///
				plotregion(style(none)) ///
				graphregion(color(white)) ///
				nodraw				
				}
				*end
		graph combine official remittances private, ycommon row(1) nodraw ///
			graphregion(color(white)) ///
			title("Financial Flows in billions of current USD", color(black) box bexpand bcolor("217 217 217")) ///
			name(panela, replace)
		graph display, ysize(2) xsize(4)
	
	*Panel B
	*establish locals for loop
		local flow1 official 
		local flow2 remittances
		local flow3 private
		local color1 "15 111 198" 
		local color2 "16 207 115" 
		local color3 "4 97 123"
		local title1 "Net Official (ODA + OOF)" 
		local title2 "Remittances" 
		local title3 "Net Private"
		local yscale1 ""
		local yscale2 off
		local yscale3 off
	*graphs
		forvalues i = 1/3{
			twoway line sh_epol_`flow`i'' year, lcolor("`color`i''") lwidth(medthick) || ///
				scatter sh_epol_`flow`i'' year if ends==1, msize(large) mcolor("`color`i''") || ///
				line sh_`flow`i'' year, lcolor("166 166 166") lwidth(medthick) || ///
				scatter sh_`flow`i'' year if ends==1, msize(large) mcolor("166 166 166") ///
				legend(off) ///
				title("`title`i''", color(black)) ///
				ytitle("") xtitle("") ///
				xlabel(1995(5)2012, notick) xscale(noline) ///
				ylabel(, grid angle(0) notick) yscale(`yscale`i'' noline) ///
				name(`flow`i'', replace) ///
				plotregion(style(none)) ///
				graphregion(color(white)) ///
				nodraw				
				}
				*end
		graph combine official remittances private, ycommon row(1) nodraw ///
			graphregion(color(white)) ///
			title("Financial Flows, share of total flows (%)", color(black) box bexpand bcolor("217 217 217")) ///
			note("Source: Official and Private Flows (OECD); Remittances (The World Bank)" ///
				"Note: Sample of 78 countries constant across all 12 years (constant sample); interpolated where data was missing", ///
				size(vsmall)) name(panelb, replace)
		graph display, ysize(2) xsize(4)
	*Combine Panel A and B
		graph combine panela panelb, row(2)
		graph export "$graph\ff_fig1.pdf", replace

		
		
		
*** FIGURE 2 ***

*Setup
	*all dev
		use "$output\financialflows_const.dta", clear
		collapse (sum) epol_oda epol_oof epol_remittances epol_private, by(year)
		gen epol_official = epol_oda + epol_oof
			lab var epol_official "ODA and other offical flows"
			drop epol_oda epol_oof
		foreach v of varlist epol_remittances-epol_official{
			replace `v' = `v'/1000 //convert to billions
			}
		keep year epol_official epol_remittances epol_private
		gen ldc = 3
		order year ldc epol_remittances epol_private epol_official
		tempfile availability
		save `availability'
	*ldc and other
		use "$output\financialflows_const.dta", clear
		count if ldc==2 & year==2012
			global count_ldc = `r(N)'
		count if ldc==1 & year==2012
			global count_other = `r(N)'
			global count_all = $count_ldc + $count_other
		collapse (sum) epol_oda epol_oof epol_remittances epol_private, by(ldc year)
		gen epol_official = epol_oda + epol_oof
			lab var epol_official "ODA and other offical flows"
			drop epol_oda epol_oof
		foreach v of varlist epol_remittances-epol_official{
			replace `v' = `v'/1000 //convert to billions
			}
		append using `availability'
			label define ldc_2 3 "All", add
		gen ends = 1 if inlist(year, 1995, 2012)
		gen labelo = "Official" if year==2012
		gen labelr = "Remittances" if year==2012
		gen labelp = "Private" if year==2012
	*stacked area variables
		gen sa_official = epol_official
		gen sa_remittances = sa_official + epol_remittances
		gen sa_private = sa_remittances + epol_private
	*shares
		gen totflow_c = epol_remittances + epol_private + epol_official
		foreach f of varlist epol_remittances-epol_official{
			gen sh_`f' = (`f'/totflow_c)*100
			}
			*end
	
	*Area graphs
	*establish locals for loop
		local name1 alldev_area
		local name2 ldc_area
		local name3 othdev_area
		local group1 "ldc==3"
		local group2 "ldc==2"
		local group3 "ldc==1"
		local title1 "Total current billions USD"
		local title2 ""
		local title3 ""
		local ytitle1 "All Developing (n=$count_all)"
		local ytitle2 "LDC (n=$count_ldc)"
		local ytitle3 "Other Developing (n=$count_other)"
		local ylabel1 0(100)600
		local ylabel2 0(10)60
		local ylabel3 0(100)600
	*graphs
		forvalues i = 1/3{
			twoway area sa_private sa_remittances sa_official year if `group`i'', ///
				xlabel(1995(5)2012, notick) xscale(noline) ///
				ylabel(`ylabel`i'', grid angle(0) notick) yscale(noline) ///
				legend(off) ///
				title("`title`i''", color(black)) ///
				ytitle("{bf:`ytitle`i''}") xtitle("") ///
				name(`name`i'', replace) ///
				plotregion(style(none)) ///
				graphregion(color(white)) ///
				color("4 97 123" "16 207 115" "15 111 198") ///
				nodraw	
				}
				*end
	
	*Shares of Total Graphs
	*establish locals for loop
		local name1 alldev_share
		local name2 ldc_share
		local name3 othdev_share
		local group1 "ldc==3"
		local group2 "ldc==2"
		local group3 "ldc==1"
		local title1 "Share of Total, %"
		local title2 ""
		local title3 ""
		local ylabel1 0(25)100
		local ylabel2 0(25)100
		local ylabel3 0(25)100
	*graphs 
		forvalues i = 1/3{
			twoway line sh_epol_official year if `group`i'', lcolor("15 111 198" ) lwidth(medthick) ylabel(`ylabel`i'') || ///
				scatter sh_epol_official year if `group`i'' & ends==1, msize(large) mcolor("15 111 198") ylabel(`ylabel`i'') || ///
				scatter sh_epol_official year if ends==1 & `group`i'' & `i'==1, msize(large) ///
					mcolor("15 111 198") mlabel(labelo) mlabposition(6) mlabcolor(black) || ///
				line sh_epol_remittances year if `group`i'', lcolor("16 207 115" ) lwidth(medthick) ylabel(`ylabel`i'') || ///
				scatter sh_epol_remittances year if `group`i'' & ends==1, msize(large) mcolor("16 207 115") ylabel(`ylabel`i'') || ///
				scatter sh_epol_remittances year if ends==1 & `group`i'' & `i'==1, msize(large) ///
					mcolor("16 207 115") mlabel(labelr) mlabposition(12) mlabcolor(black) || ///
				line sh_epol_private year if `group`i'', lcolor("4 97 123") lwidth(medthick) ylabel(`ylabel`i'') || ///
				scatter sh_epol_private year if `group`i'' & ends==1, msize(large) mcolor("4 97 123")  || ///
				scatter sh_epol_private year if ends==1 & `group`i'' & `i'==1, msize(large) ///
					mcolor("4 97 123") mlabel(labelp) mlabposition(12) mlabcolor(black)  ///
				legend(off) ///
				title("`title`i''", color(black)) ///
				ytitle("") xtitle("") ///
				xlabel(1995(5)2012, notick) xscale(noline) ///
				ylabel(0(25)100, angle(0) notick) yscale( noline) ///
				name(`name`i'', replace) ///
				plotregion(style(none)) ///
				graphregion(color(white)) ///
				nodraw				
				}
				*end
				
	*combine graphs
		graph combine alldev_area alldev_share ldc_area ldc_share othdev_area othdev_share, row(3) col(2) ///
			graphregion(color(white)) nodraw ///
			title("Financial Flows Across Income Levels", color(black) box bexpand bcolor("217 217 217")) ///
			note("Source: Official and Private Flows (OECD); Remittances (The World Bank)" ///
				"Note: Sample of 78 countries constant across all 12 years (constant sample); interpolated where data was missing", ///
				size(vsmall))
		graph display, ysize(5) xsize(4)
		graph export "$graph\ff_fig2a.pdf", replace


		
		
*** FIGURE 2b ***

*Setup
	use "$output\financialflows_const.dta", clear
		
		count if ldc==2 & year==2012
			global count_ldc = `r(N)'
		count if ldc==1 & year==2012
			global count_other = `r(N)'
			global count_all = $count_ldc + $count_other
			
	*Avg over 2008-2012 (keep obs in timeframe)
		keep if year>=2008 & year<=2012
				
	*create variable - official flows
		gen epol_official = epol_oda + epol_oof
		lab var epol_official "ODA and other offical flows"
			
	*create variable - total flows
		gen totflow = epol_official + epol_remittances + epol_private
		
	*convert to share of total at country level (unweighted average)
		foreach f in epol_official epol_remittances epol_private {
			gen sh_`f' = (`f'/totflow)*100
		}

	*locals for collpase
		local flows epol_official epol_private epol_remittances totflow
		local shares sh_epol_official sh_epol_remittances sh_epol_private
	*collapse
		collapse `flows' `shares', by(ldc)
		ds epol_* totflow
		foreach v in `r(varlist)'{
			replace `v' = `v'/1000 //convert to billions
			}
		*end
	*shares of aggregate
		foreach f in official remittances private{
			gen agsh_`f' = (epol_`f'/totflow)*100
		}
		*end
	
	*unweighted
	local count = 1
	foreach f in official remittances private{
		rename sh_epol_`f' fsh`count'
		local count = 1 + `count'
		}
		*end
	*weighted
	local count = 4
	foreach f in official remittances private{
		rename agsh_`f' fsh`count'
		local count = 1 + `count'
		}
		*end
		
	keep ldc fsh*
	reshape long fsh, i(ldc) j(flow)
		lab def flow 1 "Official" 2 "Remittances" 3 "Private"
		lab val flow flow
	gen weighted = cond(flow<4,2,1)
		lab var weighted "Weighted Average"
		lab def weighted 1 "Weighted" 2 "Unweighted"
		lab val weighted weighted
	recode flow (4=1) (5=2) (6=3)
	order ldc weighted flow
	tempfile base
	save `base'
	
	keep if ldc==2
	drop ldc
	reshape wide fsh, i(weight)  j(flow)
	gen ldc = 2
	tempfile ldc
	save `ldc'
	
	use `base'
	keep if ldc==1
	drop ldc
	reshape wide fsh, i(weight)  j(flow)
	gen ldc=1
	append using `ldc'
	
	order ldc weighted
	recode ldc (1=2) (2=1)
		lab def ldc 1 "LDC (n=$count_ldc)" 2 "Other Developing (n=$count_other)"
		lab val ldc ldc
	
	rename fsh1 official
	rename fsh2 remittances
	rename fsh3 private
	*gen spacers between bars
		gen space1 = 70 - official
		gen space2 = 60 - remittances
		gen space3 = 35 - private
	egen id = group(ldc weight)
	
	graph hbar (asis) official space1 remittances space2 private space3, ///
		over(weighted) over(ldc, label(angle(vertical))) stack ///
		bar(1, fcolor("15 111 198") lcolor("15 111 198")) ///
		bar(2, fcolor(none) lcolor(white)) ///
		bar(3, fcolor("16 207 115") lcolor("16 207 115") ) ///
		bar(4, fcolor(none) lcolor(white)) ///
		bar(5, fcolor("4 97 123") lcolor("4 97 123") ) ///
		bar(6, fcolor(none) lcolor(white) ) ///
		blabel(bar, color(white) position(center) format(%3.0f)) ///
		title("Share of Total Average Financial Flows (%)", color(black) box bexpand bcolor("217 217 217")) ///
		plotregion(style(none)) ///
		graphregion(color(white)) ///
		ytitle("") ylabel(,nogrid) yscale(off) ///
		legend(off) ///
		note("Source: Official and Private Flows (OECD); Remittances (The World Bank)" ///
			"Note: County averages between 2008-2012 (Constant Sample)", ///
			size(vsmall))
		graph export "$graph\ff_fig2b.pdf", replace

* Figure 3

*Check Share of GDP % (unweighted) for Other Developing [Figure 2 (ALT))				
		  		
	use "$output\financialflows_const.dta", clear			
				
	*create total flow			
		qui: gen totflow = epol_oda + epol_oof + epol_private + epol_remittances		
			lab var totflow "Total Financial Flows"	
				
	*gen official			
		qui: gen epol_official = epol_oda + epol_oof		
			lab var epol_official "ODA and other offical flows"	
					
	*country level unweighted average			
		*gen country shares (for countries with tax data)		
			foreach f in official private remittances{	
				qui: gen ysh_`f' = epol_`f'/gdp   // share of gdp
			}	
			*end	

	*collapse			
		collapse (sum) epol_* totflow gdp (mean) ysh_*, by(ldc year)		
	*create aggregate share
		
	*convert to billions (already millions)			
		qui: ds epol_* totflow gdp
		foreach v of varlist epol* totflow gdp{		
			qui: replace `v' = `v'/1000	
		}		
		*end		
	
