*Graphs for Financing Flow Paper

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
				ytitle("") xtitle("") ///
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
				scatter sh_epol_official year if ends==1 & `i'==3, msize(medlarge) ///
					mcolor("15 111 198") mlabel(labelo) mlabposition(6) mlabcolor(black) || ///
				line sh_epol_remittances year if `group`i'', lcolor("16 207 115" ) lwidth(medthick) ylabel(`ylabel`i'') || ///
				scatter sh_epol_remittances year if `group`i'' & ends==1, msize(large) mcolor("16 207 115") ylabel(`ylabel`i'') || ///
				scatter sh_epol_remittances year if ends==1 & `i'==3, msize(medlarge) ///
					mcolor("16 207 115") mlabel(labelr) mlabposition(6) mlabcolor(black) || ///
				line sh_epol_private year if `group`i'', lcolor("4 97 123") lwidth(medthick) ylabel(`ylabel`i'') || ///
				scatter sh_epol_private year if `group`i'' & ends==1, msize(large) mcolor("4 97 123")  ///
				scatter sh_epol_`group`i'' year if ends==1 & `i'==3, msize(medlarge) ///
					mcolor("4 97 123") mlabel(labelp) mlabposition(6) mlabcolor(black) || ///
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
				"Note: Sample of 78 countries constant across all 12 years (constant sample); interpolated where datawas missing", ///
				size(vsmall))
		graph display, ysize(5) xsize(4)
		graph export "$graph\ff_fig2.pdf", replace

		

				
