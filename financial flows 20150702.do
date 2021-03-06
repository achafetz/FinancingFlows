**************************
**    Financial Flows	**
**                      **
**     Aaron Chafetz    **
**     USAID/E3/PLC     **
**     May 21, 2015     **
**   Last Updated 7/2   **
**************************

/*
////////////////////////////////////////////////////////////////////////////////
  
  Outline
	- INITIAL SETUP
	- IMPORT AND CLEAN DATA
	- MERGE
	- REPORTS & RANKINGS
	- IDENTIFY CONSTANT SAMPLE
	- CONSTANT SAMPLE EXPORTS
	- INITIAL FIGURES
	- REVENUE SHARES (WDI)
	- EXPORT ADDITIONAL DATA FOR FIGURES
	- 
 Data sources
	- World Bank WDI
	- UNCTAD
	- OECD
	- IMF - WEO & GFS
	
////////////////////////////////////////////////////////////////////////////////	
*/


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
	
** IMPORT AND CLEAN DATA **

*import concordance file
	import excel "$data\CountriesUpdate.xlsx", sheet("countries combined") firstrow clear
	*make changes to wb codes to match downloaded files from WDI
		replace ctrycode_wb = "AND" if ctrycode_wb=="ADO"
		replace ctrycode_wb = "COD" if ctrycode_wb=="ZAR"
		replace ctrycode_wb = "IMN" if ctrycode_wb=="IMY"
		replace ctrycode_wb = "PSE" if ctrycode_wb=="WBG"
		replace ctrycode_wb = "ROU" if ctrycode_wb=="ROM"
		replace ctrycode_wb = "TLS" if ctrycode_wb=="TMP"
	save "$output\concordance.dta", replace
	
*OECD Data - ODA, OOF, and Private Flows
	*http://stats.oecd.org/qwids/
	
	foreach f in OOF Private ODA {
		import excel "$data\`f'.xlsx", sheet("`f'") firstrow clear

		*label years
			foreach year of var B-BC{
					local l`year' : variable label `year'
					rename `year' y`l`year''
				}
				*end
			rename Recipients ctry_oecd

		*gen unique id for reshaping
			gen id  = _n
		*reshape to have one column for year, country, and flow
			reshape long y, i(id) j(year)
			drop id
			rename y `=lower("`f'")'
			lab var `=lower("`f'")' "`f', millions current USD"
		*sort for merging
			sort ctry_oecd year 
		*save
			save "$output\`f'.dta", replace	
	}
	*end
	
	*merge OECD data together, save and delete extra files
		merge 1:1 ctry_oecd year using "$output\OOF.dta", nogen
		merge 1:1 ctry_oecd year using "$output\Private.dta", nogen
		sort ctry_oecd
		preserve
			use "$output\concordance.dta", clear
			sort ctry_oecd
			save "$output\concordance.dta", replace
		restore
	*merge with concordance to get ISO code	
		merge m:1 ctry_oecd using "$output\concordance.dta", keepusing(ctrycode_iso) 
	*preserve regional flows
		replace ctry_oecd="Developing Countries, Unspecified regional" if ctry_oecd=="Developing Countries, Unspecified"
		egen id = group(ctry_oecd) if regexm(ctry_oecd, " regional")
		tostring id, replace
		gen regiso = "RG" + id if regexm(ctry_oecd, " regional")
		replace ctrycode_iso = regiso if regexm(ctry_oecd, " regional")
		replace _merge=3 if regexm(ctry_oecd, " regional") // keep regional flows
	*drop unncessary variables
		drop if _merge!=3
		drop _merge id regiso
		
	*add source data
		ds year ctrycode_iso, not
		foreach v of varlist `r(varlist)'{
			note `v': Source: OECD QWIDS (May 21, 2015)
			}
			*end
	
		save "$output\oecd.dta", replace
		foreach f in OOF Private ODA{
			erase "$output\`f'.dta"
			}
			*end
			
*Thresholds for WB Country Classifications with GNI
	*Source - https://datahelpdesk.worldbank.org/knowledgebase/articles/378833-how-are-the-income-group-thresholds-determined
	
	import excel "$data\WB_Classification.xls", sheet("Thresholds") cellrange(A7:AP24) firstrow clear
	drop in 1/13
	drop B-O
	
	*label years
		foreach year of var P-AP{
			local l`year' : variable label `year'
			rename `year' y`l`year''
		}
		*end

	*transpose
		gen id = _n
		qui: reshape long y, i(Dataforcalendaryear) j(year)
		drop Dataforcalendaryear
		qui: reshape wide y, i(year) j(id)
		drop y1
		split y2, gen(mid) parse("-") destring ignore(",") force
			rename mid1 lowermid_l
			lab var lowermid_l "Lower middle income lower bound"
			rename mid2 lowermid_u
			lab var lowermid_u "Lower middle income upper bound"
		split y3, gen(mid) parse("-") destring ignore(",") force
			drop mid1
			rename mid2 uppermid_u
			lab var uppermid_u "Upper middle income upper bound"
		drop y2-y4
	*save
		save "$output\classlvls.dta", replace	
		
*WDI Data - Remittances, GDP, GDP (PPP), Exchange Rates, Tax Revenue
	*http://data.worldbank.org/
	local count = 1
	foreach f in GDP GDP_ppp Population Revenue_WDI Remittances Exchange CPI GNI_pc Rents_Oil Rents_Coal Rents_Forest Rents_Minr Rents_NGas Rents_TotNRes {
		
		di "Cleaning file: (`count') `f' "
		
		import excel "$data\`f'.xls", sheet("Data") cellrange(A3:BF251) firstrow clear
		
		*label years
			foreach year of var E-BF{
					local l`year' : variable label `year'
					rename `year' y`l`year''
				}
				*end
		*drop indicator variables
			drop IndicatorName IndicatorCode
			
		*rename for merge with concordance file 
			rename CountryName ctry_wb
			rename CountryCode ctrycode_wb
			
		*gen unique id for reshaping
			gen id  = _n
			
		*reshape to have one column for year, country, and flow
			qui: reshape long y, i(id) j(year)
			qui: drop id
			if `count' <= 5 qui: replace y = y/1000000 //Convert to millions for consistency
			if `count' == 5 disp as error "Remaing variables will not be converted into millions"
			rename y `=lower("`f'")'
		*rename variables
			if "`f'" == "GDP_ppp" lab var `=lower("`f'")' "GDP PPP, millions current international $"
			else if "`f'" == "Population" lab var `=lower("`f'")' "Population, millions"
			else if "`f'" == "Exchange" lab var `=lower("`f'")' "Official exchange rate (LCU per US$, period average)"
			else if "`f'" == "Revenue_WDI" lab var `=lower("`f'")' "Tax Revenue (millions current LCU)"
			else if "`f'" == "CPI" lab var `=lower("`f'")' "US CPI (2010 = 100)"
			else if "`f'" == "GNI_pc" lab var `=lower("`f'")' "GNI per capita, Atlas method (current US$)"
			else if "`f'" == "Rents_Oil" lab var `=lower("`f'")' "Oil rents, (% of GDP)"
			else if "`f'" == "Rents_Oil" lab var `=lower("`f'")' "Oil rents, (% of GDP)"
			else if "`f'" == "Rents_Coal" lab var `=lower("`f'")' "Coal rents, (% of GDP)"
			else if "`f'" == "Rents_Forest" lab var `=lower("`f'")' "Forest rents, (% of GDP)"
			else if "`f'" == "Rents_Minr" lab var `=lower("`f'")' "Mineral rents, (% of GDP)"
			else if "`f'" == "Rents_NGas" lab var `=lower("`f'")' "Natural gas rents, (% of GDP)"
			else if "`f'" == "Rents_TotNRes" lab var `=lower("`f'")' "Total natural resource rents, (% of GDP)"
			else lab var `=lower("`f'")' "`f', millions current USD"
			
		*sort for merging
			sort ctry_wb year 
		
		*edit CPI (not merged into WDI; will merge in later with full country list)
			if "`f'" == "CPI"{
				qui: gen cpi_d = cpi/100
					lab var cpi_d "US CPI Deflator (2010 base)"
				qui: keep if ctrycode_wb=="USA"
				qui: drop ctry_wb ctrycode_wb cpi
				note cpi_d: Source: World Bank WDI (June 2, 2015)
			}
		*save
			qui: save "$output\`f'.dta", replace
			
		local count = `count' + 1
		}
		*end
		

	*merge WB data together, save and delete extra files
		use "$output\Remittances.dta", clear
		foreach f in GDP GDP_ppp Population Revenue_WDI Exchange GNI_pc Rents_Oil Rents_Coal Rents_Forest Rents_Minr Rents_NGas Rents_TotNRes {
			di "Merging file: `f'"
			qui: merge 1:1 ctry_wb year using "$output\`f'.dta", nogen
			}
			*end
		qui: merge m:1 year using "$output\classlvls.dta", nogen //for yearly ctry classification
			di "Merging file: classlvls"
		
	*clean
		replace ctrycode_wb = "KSV" if ctry_wb=="Kosovo" 
		sort ctrycode_wb
		preserve
			use "$output\concordance.dta", clear
			sort ctrycode_wb
			save "$output\concordance.dta", replace
		restore
		merge m:1 ctrycode_wb using "$output\concordance.dta", keepusing(ctrycode_iso) // merge with concordance to get ISO code	
			drop if _merge!=3
			drop _merge
		foreach f in GDP GDP_ppp Population Revenue_WDI Remittances Exchange GNI_pc Rents_Oil Rents_Coal Rents_Forest Rents_Minr Rents_NGas Rents_TotNRes classlvls{
			erase "$output\`f'.dta"
			}
			*end
		
		sort ctry_wb year
		
	*add yearly country classification (staring in 1988)
		gen yrlyinclvl = .
		replace yrlyinclvl = 1 if gni_pc < lowermid_l
		replace yrlyinclvl = 2 if gni_pc >= lowermid_l & gni_pc <= lowermid_u
		replace yrlyinclvl = 3 if gni_pc > lowermid_u & gni_pc <= uppermid_u
		replace yrlyinclvl = 4 if gni_pc > uppermid_u & gni_pc!=.
		replace yrlyinclvl=. if year<1988
		lab var yrlyinclvl "WB Annual Country Classification"
			lab def yrlyinclvl 1 "Lower income" 2 " Lower middle income" ///
				3 "Upper middle income" 4 "High income"
			lab val yrlyinclvl yrlyinclvl
		drop lowermid_l lowermid_u uppermid_u
	
	*add resource dependence variable
		ds rents_*
		format `r(varlist)' %2.1f
		/*table year, c(m rents_oil m rents_coal m rents_forest m rents_minr m rents_ngas)
		table year, c(n rents_totnres m rents_totnres sem rents_totnres p75 rents_totnres max rents_totnres)
		table year if rents_totnres>=20, c(n rents_totnres)
		list ctry_wb rents_* if year==2000 & rents_totnres>=20, clean noobs
		*/
		bysort ctry_wb: egen avg_totnres = mean(rents_totnres) if year>=2008
		/*hist avg_totnres, freq
		graph box avg_totnres
		sum avg_totnres, d
		sum avg_totnres if avg_totnres>15 & year==2010
		centile avg_totnres if year==2010, centile(10(10)90)
		preserve
			keep if year==2010
			gsort - avg_totnres
			list ctry_wb avg_totnres in 1/20, clean
		restore
		*/
		gen nresdep_temp = cond(avg_totnres>=15 & avg_totnres!=.,2,1)
		bysort ctry_wb: egen nresdep = max(nresdep_temp)
			drop nresdep_temp
			lab def yn 1 "No" 2 "Yes"
			lab val nresdep yn
			lab var nresdep "Natural Resource Dependence"
			note nresdep: derived from WDI Total Natural Resource Rents where ctry avg between 2008-2012 is >=15% of GDP (top 20% of countries)
		
	*add source data
		ds year ctrycode_iso rents_*, not
		foreach v of varlist `r(varlist)'{
			note `v': Source: World Bank WDI (May 21, 2015)
			}
			*end
		ds rents_*
		foreach v of varlist `r(varlist)'{
			note `v': Source: World Bank WDI (June 18, 2015)
			}
			*end
			
	*convert LCU tax revenue into USD
		gen taxrev = revenue_wdi/exchange
			lab var taxrev "Tax Revenue (central government), millions current USD"
			note taxrev: Source: Derived from World Bank WDI data (May 26, 2015)
		drop revenue_wdi

	*save
		save "$output\wdi.dta", replace
	
		
*UNCTAD - Remittances
	*http://unctadstat.unctad.org/wds/ReportFolders/reportFolders.aspx
	*note - comparing this to WDI remittances; least developed countried noted in concordance file
	
	import excel "$data\RemittancesUNCTAD.xlsx", sheet("us_remittances_78357455338942") cellrange(A5:AI441) firstrow clear
		/*data slightly altered for continuity: copied data from 3 countries 
			before split for Ethiopia (1991),Indonesia (2002), and Sudan (2011)*/
			
	rename YEAR ctry_unctad
	lab var ctry_unctad ctry_unctad
	drop if ctry_unctad == "ECONOMY" | ctry_unctad=="Individual economies"
	
	*label years
		foreach year of var B-AI{
			local l`year' : variable label `year'
			rename `year' y`l`year''
			}
			*end
		
	*gen unique id for reshaping
		gen id  = _n		
	*reshape to have one column for year, country, and flow
		reshape long y, i(id) j(year)
		drop id
		rename y remittances_unctad
		lab var remittances_unctad "Personal remittances, current USD & exchange rates in millions"
	*destring
		destring remittances_unctad, replace ignore ("-")
	*sort for merging
		sort ctry_unctad year 
		preserve
			use "$output\concordance.dta", clear
			sort ctry_unctad
			save "$output\concordance.dta", replace
		restore
		merge m:1 ctry_unctad using "$output\concordance.dta", keepusing(ctrycode_iso) // merge with concordance to get ISO code	
			drop if _merge!=3
			drop _merge	
	*source data
		note remittances_unctad: Source: UNCTAD (May 22, 2015)
	*save
		save "$output\unctad.dta", replace	
		
*IMF - Revenues, tax and non tax
	*http://data.imf.org/?sk=0C6E53F6-938F-4111-B8F0-31306DF7AA59&ss=1414688546116
	
	import delimited "$data\Revenues.csv", clear 

	*eliminate noncash account
		keep if accountingmethodname=="Cash"

	*drop unnecessary variables
		drop indicatorcode sectorname sectorcode accountingmethodname ///
			accountingmethodcode countrycode status
	*keep only top level revenue types
		keep if inlist(indicatorname, ///
			"Government Revenue, Social Contributions, 2001 Manual, National Currency", ///
			"Government Revenue, Tax, 2001 Manual, National Currency", ///
			"Government Revenue, 2001 Manual, National Currency", ///
			"Government Revenue, Other Revenue, 2001 Manual, National Currency", ///
			"Government Revenue, Grants, 2001 Manual, National Currency")

		sort countryname time
		
	*convert to millions
		replace value= value/1000000
		
	*create groups/numerica variables for reshaping
		egen id = group(countryname time)
		encode indicatorname, gen(indicator)
			drop indicatorname
	*reshape so one column per revenue type
		reshape wide value, i(id) j(indicator)
	*rename variables
		rename value1 rev_total
			lab var rev_total "Total General Government Revenue, millions National Currency"
		rename value2 rev_grants
			lab var rev_grants 	"Revenue from Grants, millions National Currency"
		rename value3 rev_other
			lab var rev_other "Other Revenue, millions National Currency"
		rename value4 rev_social
			lab var rev_social "Revenue from Social Contributions, 2001 Manual, millions National Currency"
		rename value5 rev_tax
			lab var rev_tax "Tax General Government Revenue, millions National Currency"
		rename countryname ctry_imf
		rename time year
		
		drop id
		order ctry_imf year
		
	*generate non tax revenue variable
		gen rev_nontax = rev_total-rev_tax
			lab var rev_nontax "Non-tax General Government Revenue, millions National Currency"

			*drop non tax revenue variables
		keep ctry_imf year rev_tax rev_nontax

	*merge in iso
		merge m:1 ctry_imf using "$output\concordance.dta", keepusing(ctrycode_iso) // merge with concordance to get ISO code	
			drop if _merge==2
			drop _merge
		replace ctrycode_iso = "ME1" if ctry_imf=="Serbia and Montenegro"
		replace ctrycode_iso = "PSE" if ctry_imf=="West Bank and Gaza"
	*add source data
		note rev_tax: Source: IMF GFS (May 22, 2015)
		note rev_nontax: Dervived from IMF GFS data (May 22, 2015)
	*save
		save "$output\imf.dta", replace		

*IMF WEO - General Revenue
	*http://www.imf.org/external/pubs/ft/weo/2015/01/weodata/download.aspx
	
	import excel "$data\RevenuesWEO.xlsx", firstrow clear

	*label years
		foreach year of var J-AX{
			local l`year' : variable label `year'
			rename `year' y`l`year''
			}
			*end
	*destring
		destring y1980-y2020, replace ignore("n/a" "--") 			
	*eliminate excess variables
		keep if inlist(WEOSubjectCode, "NGDP", "NGDPD", "GGR", "GGR_NGDP")
		drop WEOCountryCode SubjectDescriptor SubjectNotes Units Scale CountrySeriesspecificNotes
	*remove estimates
		drop y2016-y2020
	*gen unique id for reshaping
		gen id = _n
		encode WEOSubjectCode, gen(indicator)
		drop WEOSubjectCode
	*reshape 
		reshape long y, i(id) j(year)
		drop id
	*remove estimates
		replace y=. if year>EstimatesStartAfter
		drop EstimatesStartAfter
	*gen country id for reshaping
		egen id  = group(Country year)
		reshape wide y, i(id) j(indicator)
		drop id
		order Country ISO year
	*rename
		rename Country ctry_imf
		rename ISO ctrycode_iso
		rename y1 genrev
			lab var genrev "General Government Revenue, billions National Currency"
			note genrev: "Revenue consists of taxes, social contributions, grants receivable, and other revenue. Revenue increases government?s net worth, which is the difference between its assets and liabilities (GFSM 2001, paragraph 4.20). Note: Transactions that merely change the composition of the balance sheet do not change the net worth position, for example, proceeds from sales of nonfinancial and financial assets or incurrence of liabilities."
		rename y2 genrev_pctgdp
			lab var genrev_pctgdp "General Government Revenue, percent of GDP"	
			note genrev_pctgdp: "Revenue consists of taxes, social contributions, grants receivable, and other revenue. Revenue increases government?s net worth, which is the difference between its assets and liabilities (GFSM 2001, paragraph 4.20). Note: Transactions that merely change the composition of the balance sheet do not change the net worth position, for example, proceeds from sales of nonfinancial and financial assets or incurrence of liabilities."
		rename y3 gdp_weo
			lab var gdp_weo "Gross domestic product, billions USD current prices"	
			note gdp_weo: "Expressed in billions of national currency units . Expenditure-based GDP is total final expenditures at purchasers? prices (including the f.o.b. value of exports of goods and services), less the f.o.b. value of imports of goods and services. [SNA 1993]"
		rename y4 gdp_usd_weo
			lab var gdp_usd_weo "Gross domestic product, billions Nat'l currency current prices"	
			note gdp_usd_weo: "Values are based upon GDP in national currency converted to U.S. dollars using market exchange rates (yearly average). Exchange rate projections are provided by country economists for the group of other emerging market and developing countries. Exchanges rates for advanced economies are established in the WEO assumptions for each WEO exercise. Expenditure-based GDP is total final expenditures at purchasers? prices (including the f.o.b. value of exports of goods and services), less the f.o.b. value of imports of goods and services. [SNA 1993]"
	*ISO changes
		replace ctrycode_iso="na_ode_iso115" if ctry_imf=="Kosovo"
		replace ctrycode_iso="XX1" if ctry_imf=="Taiwan Province of China"
	
	*add source 
		ds g*
		foreach v of varlist `r(varlist)'{
			note `v': Source: IMF WEO database (May 26, 2015)
			}
			*end
	*save
		save "$output\weo.dta", replace
	
*ICTDGRD - Government Tax Revenue 
* Source: http://www.ictd.ac/en/about-ictd-government-revenue-dataset#Dataset
	
	use "$data\ICTDGRDmerged_edited.dta", clear
	
	*rename iso codes for merging
		replace iso = "na_ode_iso115" if country=="Kosovo"
		replace iso = "COD" if country=="Congo, Dem. Rep."
		replace iso = "TLS" if country=="Timor-Leste"
		replace iso = "PSE" if country=="West Bank and Gaza"
		rename  iso ctrycode_iso
	*keep only some of the variables
		keep year ctrycode tot_resource_rev tot_nresource_rev_inc_sc ///
			resource_taxes	nresource_tax_inc_sc nresource_tax_ex_sc ///
			nresource_nontax resource_nontax social_contrib grants
			
	*add "(% of GDP)" to label
		foreach v of varlist rev_inc_sc - trade{
			local label : variable label `v'		
			lab var `v' "`label' (% of GDP)"
			}
			*end
			
	*add source data
		ds year ctrycode_iso, not
		foreach v of varlist `r(varlist)'{
			note `v': Source: ICTDGRD (June 8, 2015)
			}
			*end
				
	save "$output\ICTDGRDtax.dta", replace

*Mike Crosswell's  Strategic Indicators (USAID) 

	import excel "$data\Strategic Indicators 2015_soc.xlsx", sheet("Export") firstrow clear
		keep country iso cpia* kkstab04 - oecdfrag15
		rename iso ctrycode_iso
		drop if ctrycode_iso==""
	*destring variables
		destring cpia06-kkstab11 ppcfrag-fsindex09 fsindex10-fsindextrend, replace ignore("NA") 
		lab def yn 1 "No" 2 "Yes"
		recode ppcfrag (1 = 2) (0 = 1)
		lab val ppcfrag yn
		foreach v of varlist cfsibrd oecdfrag13-oecdfrag15{
			replace `v' = "1" if `v'=="No"
			replace `v' = "2" if `v'=="Yes"
			destring `v', replace
			lab val `v' yn
		}
		*end
			
	*label fragility variables
		lab var cpia06 "CPIA 2006 (2005)"
		lab var cpia07 "CPIA 2007 (2006)"
		lab var cpia08 "CPIA 2008 (2007)"
		lab var cpia09 "CPIA 2009 (2008)"
		lab var cpia10 "CPIA 2010 (2009)"
		lab var cpia11 "CPIA 2011 (2010)"
		lab var cpia12 "CPIA 2012 (2011)"
		lab var cpia13 "CPIA 2013 (2012)"
		lab var cpia14 "CPIA 2014 (2013)"
		lab var kkstab04 "KK Instability 2004"
		lab var kkstab05 "KK Instability 2005"
		lab var kkstab06 "KK Instability 2006"
		lab var kkstab07 "KK Instability 2007"
		lab var kkstab08 "KK Instability 2008"
		lab var kkstab09 "KK Stability 2009"
		lab var kkstab10 "KK Stability 2010"
		lab var kkstab11 "KK Stability 2011 "
		lab var kkstab12 "KK Stability 2012"
		lab var kkstab13 "KK Stability 2013"
		lab var kkstab14 "KK Stability 2014"
		lab var kkstabtrend "Stability Trend  "
		lab var ppcfrag "PPC Fragility Test "
		lab var fsindex08 "Failed States Index "
		lab var fsindex09 "Failed States Index "
		lab var cfsibrd "Core Fragile States IBRD"
		lab var fsindex10 "Failed States Index "
		lab var fsindex11 "Failed States Index "
		lab var fsindex12 "Failed States Index "
		lab var fsindex13 "Failed States Index "
		lab var fsindex14 "Fragile States Index "
		lab var fsindextrend "Fragile States Trend "
		lab var oecdfrag13 "OECD Fragile 2013?"
		lab var oedfrag14 "OECD Fragile 2014?"
		lab var oecdfrag15 "OECD Fragile 2015?"

			*add source data
			ds country ctrycode_iso, not
			foreach v of varlist `r(varlist)'{
				note `v': Source: Mike Crosswell (USAID) Strategic Indicators (updated April 1, 2015)
				}
				*end
		*save
			save "$output\fragility.dta", replace
*IMF
	use "$data\IMFRevMobilization2015.dta", clear		
	
	*set as timeseries and fill
		encode cname, gen(ctry)
		tsset ctry year
		tsfill, full
	*merge using wbcode
		rename wbcode ctrycode_wb
		replace ctrycode_wb = "COD" if ctrycode_wb=="ZAR"
		rename tax taxr 
		merge m:1 ctrycode_wb using "$output\concordance.dta", keepusing(ctrycode_iso) // merge with concordance to get ISO code	
			keep if _merge==3
			drop _merge
	
	*add source
		ds cname ccode ctrycode_wb year *_src, not
		foreach v of varlist `r(varlist)'{
				note `v': Source: IMF Fiscal Affairs Department's Revenue Database (June 19, 2015)
				}
				*end
	*save
		save "$output\imfrev.dta", replace
		
		
* GFS Govt Expenditures
	*http://elibrary-data.imf.org/QueryBuilder.aspx?key=19784658&s=322
	*Imported cash only at general government level
	
	disp as error "Data not publically avaialable. Data not stored on GitHub"
	import excel "$data\Govt_Expenditures.xlsx", sheet("DATA") firstrow clear
	
	*encode/destring 
		encode ConceptLabel, gen(type)
		destring TimeLabel, gen(year)
	*rename
		rename CountryLabel ctry_imf
		rename Value value
	*eliminate extraneous variables
		keep type ctry_imf year value
	*convert to millions
		replace value = value/1000
	*create group/numerical variables for reshaping
		egen id = group(ctry_im year)
	*reshape for one column per expenditure type 
		reshape wide value, i(id) j(type)
		drop id
		order ctry_imf year
	*rename and label variables
		rename value1 expetyp_emplcomp	
			lab var expetyp_emplcomp "Compensation of Employees, (gen govt) millions National Currency"
		rename value2 expetyp_consfc	
			lab var expetyp_consfc "Consumption of Fixed Capital,(gen govt) millions National Currency"
		rename value3 expfcn_defense	
			lab var expfcn_defense "Defense, (gen govt) millions National Currency"
		rename value4 expfcn_econaffairs	
			lab var expfcn_econaffairs "Economic Affairs, (gen govt) millions National Currency"
		rename value5 expfcn_educ	
			lab var expfcn_educ "Education, (gen govt) millions National Currency"
		rename value6 expfcn_envirpro	
			lab var expfcn_envirpro "Environmental Protection, (gen govt) millions National Currency"
		rename value7 expfcn_pubservices	
			lab var expfcn_pubservices "General Public Services,(gen govt) millions National Currency"
		rename value8 expfcn_health	
			lab var expfcn_health "Health, (gen govt) millions National Currency"
		rename value9 expfcn_housing	
			lab var expfcn_housing "Housing and Community Amenities, (gen govt) millions National Currency"
		rename value10 expetyp_interest	
			lab var expetyp_interest "Interest, (gen govt) millions National Currency"
		rename value11 expetyp_other	
			lab var expetyp_other "Other Expense, (gen govt) millions National Currency"
		rename value12 expfcn_safety	
			lab var expfcn_safety "Public Order and Safety, (gen govt) millions National Currency"
		rename value13 expfcn_rec	
			lab var expfcn_rec "Recreation, Culture, and Religion, (gen govt) millions National Currency"
		rename value14 expetyp_socben	
			lab var expetyp_socben "Social Benefits, (gen govt) millions National Currency"
		rename value15 expfcn_socpro	
			lab var expfcn_socpro "Social Protection, (gen govt) millions National Currency"
		rename value16 expetyp_subtran	
			lab var expetyp_subtran "Subsidies and Transfers, (gen govt) millions National Currency"
		rename value17 expetyp_totexp	
			lab var expetyp_totexp "Total Expenditure, millions (gen govt) National Currency"
		rename value18 expfcn_totoutlays	
			lab var expfcn_totoutlays "Total Outlays, millions (gen govt) National Currency"
		rename value19 expetyp_goodsservices	
			lab var expetyp_goodsservices "Use of Goods and Services, (gen govt) millions National Currency"
	*reorder
		order ctry_imf year expfcn_totoutlays expfcn_pubservices expfcn_defense ///
			expfcn_safety expfcn_econaffairs expfcn_envirpro expfcn_housing ///
			expfcn_health expfcn_rec expfcn_educ expfcn_socpro expetyp_totexp ///
			expetyp_emplcomp expetyp_goodsservices expetyp_consfc expetyp_interest ///
			expetyp_subtran expetyp_socben expetyp_other
			
	*rename country for merge
		replace ctry_imf = "Afghanistan, Islamic Republic Of" if ctry_imf=="Afghanistan, Islamic Republic of"
		replace ctry_imf = "Armenia, Republic Of" if ctry_imf=="Armenia, Republic of"
		replace ctry_imf = "Azerbaijan, Republic Of" if ctry_imf=="Azerbaijan, Republic of"
		replace ctry_imf = "Belarus, Republic Of" if ctry_imf=="Belarus"
		replace ctry_imf = "Hong Kong Special Administrative Region, People's Republic Of China" if ctry_imf=="China, P.R.: Hong Kong"
		replace ctry_imf = "Macao Special Administrative Region, People's Republic Of China" if ctry_imf=="China, P.R.: Macao"
		replace ctry_imf = "China, People's Republic Of" if ctry_imf=="China, P.R.: Mainland"
		replace ctry_imf = "Congo, Republic Of" if ctry_imf=="Congo, Republic of"
		replace ctry_imf = "Croatia, Republic Of" if ctry_imf=="Croatia"
		replace ctry_imf = "Egypt, Arab Republic Of" if ctry_imf=="Egypt"
		replace ctry_imf = "Iran, Islamic Republic Of" if ctry_imf=="Iran, Islamic Republic of"
		replace ctry_imf = "Kazakhstan, Republic Of" if ctry_imf=="Kazakhstan"
		replace ctry_imf = "Korea, Republic Of" if ctry_imf=="Korea, Republic of"
		replace ctry_imf = "Latvia, Republic Of" if ctry_imf=="Latvia"
		replace ctry_imf = "Lithuania, Republic Of" if ctry_imf=="Lithuania"
		replace ctry_imf = "Macedonia, Former Yugoslav Republic Of" if ctry_imf=="Macedonia, FYR"
		replace ctry_imf = "Moldova, Republic Of" if ctry_imf=="Moldova"
		replace ctry_imf = "Netherlands Antilles, Kingdom Of The" if ctry_imf=="Netherlands Antilles"
		replace ctry_imf = "Poland, Republic Of" if ctry_imf=="Poland"
		replace ctry_imf = "Serbia, Republic Of" if ctry_imf=="Serbia, Republic of"
		replace ctry_imf = "Tajikistan, Republic Of" if ctry_imf=="Tajikistan"
		replace ctry_imf = "Timor-Leste, Democratic Republic Of" if ctry_imf=="Timor-Leste, Dem. Rep. of"
		replace ctry_imf = "Uzbekistan, Republic Of" if ctry_imf=="Uzbekistan"
		replace ctry_imf = "Yemen, Republic Of" if ctry_imf=="Yemen, Republic of"

	*merge in iso
		merge m:1 ctry_imf using "$output\concordance.dta", keepusing(ctrycode_iso) //merge with concordance to get ISO code
 			drop if _merge==2
			drop _merge
		replace ctrycode_iso = "PSE" if ctry_imf=="West Bank and Gaza"	
		    
	*add data source
		ds ctry_imf year, not 
		foreach v of varlist `r(varlist)'{
				note `v': Source: IMF GFS (June 24, 2015)
				}
				*end
	*save
		save "$output\gfs.dta", replace
		
********************************************************************************
********************************************************************************
		
** MERGE **

	use "$output\oecd.dta", clear
	
	*merge
		merge 1:1 ctrycode_iso year using "$output\wdi.dta", nogen
		merge 1:1 ctrycode_iso year using "$output\unctad.dta", nogen
		merge 1:1 ctrycode_iso year using "$output\imf.dta", nogen
		merge 1:1 ctrycode_iso year using "$output\weo.dta", nogen
		merge 1:1 ctrycode_iso year using "$output\gfs.dta", nogen
		merge 1:1 ctrycode_iso year using "$output\imfrev.dta", ///
			keepusing(taxr) nogen
		merge m:1 ctrycode_iso using "$output\concordance.dta", ///
			keepusing(reg_wb reg_usaid inclvl_wb landlockeddev_unctad ldc_unctad status_unctad)
			replace _merge=3 if regexm(ctry_oecd, " regional") //preserve OECD regional flows
			drop if _merge!=3
			drop _merge
			drop if year>2013
		merge m:1 year using "$output\CPI.dta", nogen
		merge m:1 ctrycode_iso using "$output\fragility.dta", nogen ///
			keepusing(cpia14)
		merge 1:1 ctrycode_iso year using "$output\ICTDGRDtax.dta"
			drop if _merge==2 //remove high income countries
			drop _merge

	*create one country name
		gen ctry = ctry_wb
			replace ctry = ctry_oecd if ctry==""
			replace ctry = ctry_unctad if ctry==""
			replace ctry = ctry_imf if ctry==""
			lab var ctry "Country"
		drop ctry_oecd ctry_wb ctrycode_wb ctry_unctad ctry_imf
		rename ctrycode_iso iso
			lab var iso "ISO country code"
	*reorder
		order ctry iso year reg_wb reg_usaid inclvl_wb landlockeddev_unctad ///
			ldc_unctad status_unctad cpi_d

	*label
		lab var year "Year"
		lab var reg_wb "Region, World Bank"
		lab var reg_usaid "Region, USAID"
		lab var inclvl_wb "Income Group (2015), World Bank"
		lab var landlockeddev_unctad "Landlocked Developing Countries"
			rename landlockeddev_unctad landlockeddev
		lab var ldc_unctad "Least Developed Countries (2015), UNCTAD"
			rename ldc_unctad ldc
		lab var status_unctad "Development Status (2015), UNCTAD"
			rename status_unctad devstatus

	*encode
		foreach x of varlist reg_wb reg_usaid inclvl_wb landlockeddev ldc devstatus {
			encode `x', gen(`x'_2)
			drop `x'
			rename `x'_2 `x'
			}
		*end
		
		order ctry iso year reg_wb reg_usaid inclvl_wb landlockeddev ldc devstatus
		sort ctry year

	* drop UNCTAD remittances, source is World Bank
		drop remittances_unctad

	*drop developed countries	
		replace devstatus=3 if inlist(ctry, "Bermuda", "Croatia", "Cyprus", "Gibralter", "Kosovo", "Malta")
		replace devstatus=1 if iso=="RUS"
		replace devstatus=4 if regexm(ctry, " regional") // denotes regional flows of development aid
			label define devstatus_2 4 "Developing regions", add
		*tab ctry if devstatus==.
		drop if inlist(devstatus, 1, .)
		
	*covert all LCU figures to USD
		foreach r of varlist rev_tax rev_nontax expfcn_totoutlays-expetyp_other{
			replace `r' = `r'/exchange
			local varlabel : var label `r'
			local newlabel : subinstr local varlabel "National Currency" "current USD", all
			label variable `r' "`newlabel'"
			}
			*end
		replace genrev = (genrev/exchange)*1000
			lab var genrev "Overall revenue (general govt), millions USD"
		rename taxr taxr_pct
		gen taxr = (taxr_pct/100)*gdp
			lab var taxr "Total tax revenue (excluding social contributions), millions USD"
		*convert ICTDGRD tax revenue to current dollars
		foreach r of varlist tot_resource_rev tot_nresource_rev_inc_sc resource_taxes nresource_tax_inc_sc nresource_tax_ex_sc nresource_nontax resource_nontax social_contrib grants{
			gen trv_`r' = (`r'/100)*gdp
			local varlabel : var label `r'
			local newlabel : subinstr local varlabel "(% of GDP)" ", millions current USD", all
			label variable trv_`r' "`newlabel'"
			}
			*end
	*add fragility measure (those in the top quartile)
		*hist cpia14 if year==2013, freq bin(15)
		sum cpia14, d
		list ctry cpia14 if cpia14>=`r(p75)' & cpia14!=. & year==2013
		gen fragile = .
			note fragile: Fragility based on CPIA 2014 (World Bank)
			replace fragile=1 if cpia14!=.
			replace fragile=2 if cpia14>=`r(p75)' & cpia14!=.
			lab val fragile yn
			lab var fragile "Fragile Country (2014)"
		tab fragile if year==2013,m
			
	*compare revenue observations
		describe taxrev rev_tax genrev taxr
		notes list taxrev rev_tax genrev taxr //sources
		table year, c(n taxrev n rev_tax n genrev n taxr)
		table ctry year if year>1989, c(n taxrev n taxr)
		
	* create 2nd resouce dependence variable
		gen dep = .
			replace dep = 1 if tot_resource_rev!=. & tot_nresource_rev_inc_sc!=.
			replace dep = 2 if (year>=2005) & (tot_resource_rev>tot_nresource_rev_inc_sc)
		by ctry: egen resdep = max(dep)
			lab val resdep yn
			lab var resdep "Resource Dependent (in past 5 years)"
			note resdep: Indicated where country's resource revenue exceeded ///
				nonresource revenue in last five years of sample (2005-2010) ///
				at least once
		drop dep
	
	*set as panel dataset
		encode ctry, gen(ctry2)
			destring ctry, replace force
			replace ctry = ctry2
			lab val ctry ctry2
			drop ctry2
		xtset ctry year
		
	*drop unused variables
		drop exchange genrev_pctgdp gdp_weo gdp_usd_weo

	*save
		compress
		save "$output\financialflows.dta", replace	

********************************************************************************
********************************************************************************
		
** REPORTS & RANKINGS **
	use "$output\financialflows.dta", clear	

	*list of countries
		tab ctry
	*how many observations for each flow?
		table year, c(n oda n oof n remittances n private)
	*how many of the flow variables do countries have data for each year?
		egen nonmissing = rownonmiss(oda oof remittances private)
		recode nonmissing 0 = .
		qui: tab nonmissing, gen(obs)
		foreach v of varlist obs1-obs4{
			recode `v' 0 = .
			}
			*end
		table year, c(n obs1 n obs2 n obs3 n obs4)
		drop obs*
	*sum of flows by year (millions USD)
		table year, c(sum oda sum oof sum remittances sum private)
	*sum of flows by year for 2000 & 2012 (millions USD)
		table year if inlist(year, 2000, 2012), c(sum oda sum oof sum remittances sum private)

	*create official flows variable
		gen official = oda + oof
				lab var official "ODA and other offical flows"
	*avg pd between 2010-2012
		drop if year<2010 | year>2012
		foreach f in official private remittances{
			by ctry: egen avg_`f' = mean(`f')
			lab var avg_`f' `"Avg `=proper("`f'")' Flows (2010-2012)"'
			}
			*end
	*keep if year
		keep if year==2012
		keep ctry iso ldc avg_*
	*total flows
		egen totflow = rowtotal(avg_official avg_private avg_remittances)
			lab var totflow "Avg Total Financial Flows (2010-2012)"
			format totflow %9.0fc
	*ranking
		egen rank_oth = rank(totflow) if ldc!=2, field 	
		egen rank_oth_noreg = rank(totflow) if ldc==1, field
		egen rank_ldc = rank(totflow) if ldc==2, field
		egen rank_tot = rank(totflow), field
			 
		sort rank_oth
		list rank_oth ctry totflow in 1/10, noobs
		sort rank_oth_noreg
		list rank_oth_noreg ctry totflow in 1/10, noobs
		sort rank_ldc
		list rank_ldc ctry totflow in 1/10, noobs
		sort rank_tot
		list rank_tot ctry totflow in 1/10, noobs

	* list of countries in different groups
		*LDC
		preserve
		collapse ldc if ldc==2, by(ctry)
		list ctry, noobs clean
		restore
		
		*Fragile
		preserve
		collapse fragile if fragile==2, by(ctry)
		list ctry, noobs clean
		restore
		
		*Resource Dependence
		preserve
		collapse resdep if resdep==2, by(ctry)
		list ctry, noobs clean
		restore
		
		*Full sample & regions
		keep if year==2012
		keep ctry reg_wb
		sort reg_wb ctry
		browse
		
		*Constant Sample
		use13 "$output/financialflows_const.dta", clear
		keep if year==2012
		keep ctry reg_wb
		sort ctry
		browse

********************************************************************************
********************************************************************************

** IDENTIFY CONSTANT SAMPLE ** 
	*(full obseravtions for all years and flows)

	use "$output\financialflows.dta", clear	
	
	*identify country with all flows in a given year
		egen flowmisscount = rowmiss(oda oof private remittances)
			gen full = 2 if flowmisscount==0
			replace full = 1 if flowmisscount!=0
				drop flowmisscount
			lab var full "Country has all flows for given year"
			lab val full yn
			*observation per year
				tab year if full==2
			
	*identify countries with all flows for full time period
		foreach pdstart of numlist 1980/2005{
			preserve
			qui: drop if year==2013 //limited flow observations for 2013
			qui: drop if year<`pdstart'
			qui: by ctry: egen bookends = min(full) if inlist(year, `pdstart', 2012) // do countries have a full set of flows in 2000 and 2012?
			qui: lab val bookends yn
						qui: sum bookends if year==2012 & bookends==2
			local tot `r(N)'
			qui: sum bookends if year==2012 & bookends==2 & ldc==2
			local ldc `r(N)'
			qui: sum bookends if year==2012 & bookends==2 & nresdep==2
			local nresdep `r(N)'
			if `pdstart'==1980 di "     How many countries have full datasets with different starting years?" ///
				_newline "       YEAR        COUNTRIES     LDCs         Res Dep"
			di "       `pdstart'            `tot'          `ldc'           `nresdep'"
			restore
			}
			*end
	
	/* identify all countries that have the same start and end year and
		interpolate any missing values in between */
		by ctry: egen bookends = min(full) if inlist(year, 1995, 2012) // do countries have a full set of flows in 2000 and 2012?
		by ctry: egen include_tax = min(bookends) // project bookends onto rest of years for country
			lab val bookends include_tax yn
			
		
	*keep countries that have observations at both ends of range 
		keep if include==2
		keep if year>=1995 & year<=2012
		tab ctry if year==2012 //86 countries in constant sample
		bysort ldc: sum ctry if year==2012
	
	*interpolate between endpoints
		sort ctry year
		foreach v of varlist oda oof private remittances{
			by ctry: ipolate `v' year, gen(epol_`v') epolate
				local label : variable label `v'		
				lab var epol_`v' "Extrapolated `label'"
			}
			*end
	*drop
		drop full bookends include
		
	*save
		save "$output\financialflows_const.dta", replace
		
	*extrapolate TAX REVENUE from IMF
		*identify country with all flows in a given year
				gen full = cond(taxr!=.,2,1)
				
		/* identify all countries that have the same start and end year and
			interpolate any missing values in between */
			by ctry: egen bookends = min(full) if inlist(year, 1995, 2012) // do countries have a full set of flows in 2000 and 2012?
			by ctry: egen include_tax = min(bookends) // project bookends onto rest of years for country
				lab var include_tax "Part of TAX REVENUE constant sample"
				lab val bookends include_tax yn
				tab ctry include_tax if year==2012 
				tab include_tax ldc if year==2012
				tab include_tax nresdep if year==2012
		*interpolate between endpoints
			sort ctry year
			by ctry: ipolate taxr year if include_tax==2, gen(epol_taxr)
				local label : variable label taxr	
				lab var epol_taxr "Extrapolated `label'"
		
		*drop
			drop full bookends
	
	*save
		save "$output\financialflows_const.dta", replace

********************************************************************************
********************************************************************************

** CONSTANT SAMPLE EXPORTS **
			
*Constant Sample: Create and export sums/averages for each category
	clear
	local count = 1
	foreach t in "sum" "mean"{
		foreach x in "if ldc==2" "if ldc!=2" "if nresdep==2" "if nresdep!=2"""{
			use "$output\financialflows_const.dta", clear
			
			*create total flow
				qui: gen totflow = epol_oda + epol_oof + epol_private + epol_remittances
					lab var totflow "Total Financial Flows"
			
			di "locals: (`count') `t' & `x'"
			
			*country level average growth
				*gen official
					qui: gen epol_official = epol_oda + epol_oof
						lab var epol_official "ODA and other offical flows"
					foreach f in epol_official epol_private epol_remittances{
						qui: gen base95 = `f' if year==1995
						bysort ctry: egen flowbase = min(base95)
						qui: gen `f'_gr = (`f'/flowbase)-1
						drop base95 flowbase
						}
						*end
				*gen var for tax observations only
					foreach f in epol_official epol_private epol_remittances{
						qui: gen `f'_t = `f' if include_tax==2
						}
						*end
			*country level unweighted average
				*gen country shares (for countries with tax data)
					foreach f in official private remittances{
						qui: gen sh_`f' = epol_`f'/totflow  // share of total
						qui: gen ysh_`f' = epol_`f'/gdp // share of gdp
						qui: gen sh_`f'_t = epol_`f'/totflow  if include_tax==2 // share of total
						qui: gen ysh_`f'_t = epol_`f'/gdp  if include_tax==2 // share of gdp
					}
					*end
				*gen country shares with tax (for countries with tax data)
					qui: gen sh_tax_taxrev = epol_taxr/(totflow+epol_taxr) if include_tax==2 // tax share of total
					qui: gen epol_other = epol_official + epol_remittances + epol_private if include_tax==2
					qui: gen sh_tax_other = epol_other/(totflow+epol_taxr) if include_tax==2 // other share of total
					qui: gen ysh_tax_taxrev = epol_taxr/gdp if include_tax==2 // tax share of gdp
					qui: gen ysh_tax_other = epol_other/gdp	if include_tax==2 //other share of gdp
					
				*drop epol_official
				
			*collapse
				collapse (`t') oda oof private remittances epol_* sh_* ysh_* totflow population gdp (max) cpi_d `x', by(year)
			
			*create offical flows variable
				*qui: gen epol_official = epol_oda + epol_oof
				*	lab var epol_official "ODA and other offical flows"
			
			*create various flows
				foreach f in official private remittances{
					* per capita flows
						qui: gen pc_`f'_`t' = epol_`f'/population
						lab var pc_`f'_`t' "`=proper("`f'")' Flows per capita (`t')"
						* base for deflator
							qui: sum pc_`f'_`t' if year==1995
							global pcnombase_`f'_`t' = `r(mean)'
					* real flows, total
						qui: gen real_`f'_`t' = epol_`f'/cpi_d
						lab var real_`f'_`t' "`=proper("`f'")' Flows in real terms (`t')"
						* base for deflator
							qui: sum real_`f'_`t' if year==1995
							global realbase_`f'_`t' = `r(mean)'
					* real flows per capita
						qui: gen realpc_`f'_`t' = real_`f'_`t'/population
						lab var realpc_`f'_`t' "`=proper("`f'")' Flows per capita in real terms (`t')"
					* share of total
						qui: gen share_`f'_`t' = (epol_`f'/totflow)*100	
						lab var share_`f'_`t' "`=proper("`f'")' share of Total Flows (`t'), %"
					}
					*end	
								
			*create real and nominal % changes with a base of 1995 per capita
				foreach f in official private remittances{
					qui: sum epol_`f' if year==1995
						global nombase_`f'_`t' = `r(mean)'
					qui: gen compn_`f'_`t' = epol_`f' * (${pcnombase_`f'_`t'}/${nombase_`f'_`t'})
					qui: gen compr_`f'_`t' = real_`f'_`t' * (${pcnombase_`f'_`t'}/${realbase_`f'_`t'})
				}
				*end 
					
			*convert to billions (already millions)
				qui: ds year share_* sh_* ysh_* population* cpi_d pc_* realpc_* comp*, not
				foreach v in `r(varlist)'{
					qui: replace `v' = `v'/1000
					}
					*end

			*export
				local ffex `"qui: export excel year epol* pc* real* comp* share_* sh_* ysh_* gdp using "$excel\FFgraphs.xlsx", firstrow(variables) sheetreplace"'
				if `count' == 1 `ffex' sheet("ConstantLDCs")
				else if `count' == 2 `ffex' sheet("ConstantOther")
				else if `count' == 3 `ffex' sheet("ConstResDep")
				else if `count' == 4 `ffex' sheet("ConstNonResDep")
				else if `count' == 5 `ffex' sheet("TotConstant")
				else if `count' == 6 `ffex' sheet("ConstavgLDCs")
				else if `count' == 7 `ffex' sheet("ConstavgOther")
				else if `count' == 8 `ffex' sheet("ConstacgResDep")
				else if `count' == 9 `ffex' sheet("ConstavgNonResDep")
				else `ffex' sheet("TotConstavg") 
			clear
			local count = 1 + `count'
		}
	}
	*end

*Create LDC share of flows for all developing
	use "$output\financialflows_const.dta", clear
		*overall flows (all developing
			gen totflow = epol_oda + epol_oof + epol_private + epol_remittances	
		*collpase for total flows per year
			collapse (sum) totflow, by(year)
			lab var totflow "Total Overall Financial Flows, millions current USD (full constant sample)"
		*save for merging
			save "$output\totflows.dta", replace
			
	use "$output\financialflows_const.dta", clear
		*collapse to get sum of LDC flows
			collapse (sum) epol_* if ldc==2, by(year)
			
			*create offical flows variable
				qui: gen epol_official = epol_oda + epol_oof
					lab var epol_official "ODA and other offical flows"
			*merge with overall flows (all developing)
				merge 1:1 year using "$output\totflows.dta", nogen
					erase "$output\totflows.dta"
			* LDC share of total
				foreach f in official private remittances{
					gen overallshare_`f' = (epol_`f'/totflow)*100	
						lab var overallshare_`f' "`=proper("`f'")' share of Overall Flows, %"
				}
				*end	
		*export
			export excel year overallshare_* using "$excel\FFgraphs.xlsx", firstrow(variables) sheetreplace sheet("ConstLDCsOverallShare")	
	clear
	
	
********************************************************************************
********************************************************************************

** INITIAL FIGURES **

*LDCs
	
	use "$output\financialflows.dta", clear	
	
	*collapse
		collapse (sum) oda oof private remittances epol_taxr if ldc==2, by(year)
		
	*for stacked area (convert to billions)
		ds year, not
		foreach v in `r(varlist)'{
			replace `v' = `v'/1000
			}
			*end
		gen official = oda + oof
			lab var official "ODA and other offical flows"
		gen remit = official + remittances
			lab var remit "Remittances"
		gen priv = remit + private
			lab var priv "Private Flows"
		gen rev = priv + epol_taxr
			lab var rev "Tax Revenues"
	
		
	*export
		export excel using "$excel\FFgraphs.xlsx", sheet("LDCs") firstrow(variables) sheetreplace
		
	*LDCs financial flows
		twoway area priv remit official year if year>=2000 & year<=2011, ///
			title("Financial Flows to Least Developed Countries", position(11)) ///
			sub("in billions of current USD", position(11)) ///
			legend(order( 3 "ODA + OOF" 2 1)row(1)) ///
			xlabel(2000 (2) 2011) ///
			ylabel(0 (30) 90) ///
			note("Sources: ODA, OOF, Private Flows (OECD); Remittances (World Bank)")
		graph export "$graph/ff_ldc.pdf", replace
		
	*scale to trillions
		/*
		foreach v of varlist official remit priv rev{
			replace `v' = `v'/1000
			}
		*/
	*LDCs financial + tax revenue flows
		twoway area rev year if year>=2000 & year<=2011, lcolor(khaki) fcolor(khaki) || ///
			area priv year if year>=2000 & year<=2011, lcolor(navy) fcolor(navy) || ///
			area remit year if year>=2000 & year<=2011, lcolor(maroon) fcolor(maroon)|| ///
			area official year if year>=2000 & year<=2011, lcolor(forest_green) fcolor(forest_green) ///
			title("Financial Flows to Least Developed Countries", position(11)) ///
			sub("in billions of current USD", position(11)) ///
			legend(order( 4 "ODA + OOF" 3 2 1) row(1) size(vsmall)) ///
			xlabel(2000 (2) 2011) ///
			note("Sources: ODA, OOF, Private Flows (OECD); Remittances, Tax Revenues (World Bank)" "Note: Tax Revenues from the Central Government and are extrapolated")
		graph export "$graph/ff_ldctax.pdf", replace

*Other Developing countries (non-LDCs)
	
	use "$output/financialflows.dta", clear	
	
	*collapse
		collapse (sum) oda oof private remittances epol_taxr if ldc!=2, by(year) //includes regions (missing)
		
	*for stacked area (convert to billions)
		ds year, not
		foreach v in `r(varlist)'{
			replace `v' = `v'/1000
			}
			*end
		gen official = oda + oof
			lab var official "ODA and other offical flows"
		gen remit = official + remittances
			lab var remit "Remittances"
		gen priv = remit + private
			lab var priv "Private Flows"
		gen rev = priv + epol_taxr
			lab var rev "Tax Revenues"
	
	*export
		export excel using "$excel\FFgraphs.xlsx", sheet("Other") firstrow(variables) sheetreplace
		
	*Other Developing Countries/Regions financial flows
		twoway area priv remit official year if year>=2000 & year<=2011, ///
			title("Financial Flows to Other Developing Countries", position(11)) ///
			sub("in billions of current USD", position(11)) ///
			legend(order( 3 "ODA + OOF" 2 1)row(1)) ///
			xlabel(2000 (2) 2011) ///
			ylabel(0 (300) 900) ///
			note("Sources: ODA, OOF, Private Flows (OECD); Remittances (World Bank)")
		graph export "$graph/ff_odc.pdf", replace
		
	*scale to trillions
		
		foreach v of varlist official remit priv rev{
			replace `v' = `v'/1000
			}
		
	*Other Developing Countries financial + tax revenue flows
		twoway area rev year if year>=2000 & year<=2011, lcolor(khaki) fcolor(khaki) || ///
			area priv year if year>=2000 & year<=2011, lcolor(navy) fcolor(navy) || ///
			area remit year if year>=2000 & year<=2011, lcolor(maroon) fcolor(maroon)|| ///
			area official year if year>=2000 & year<=2011, lcolor(forest_green) fcolor(forest_green) ///
			title("Financial Flows to Other Developing Countries", position(11)) ///
			sub("in trillions of current USD", position(11)) ///
			legend(order( 4 "ODA + OOF" 3 2 1) row(1) size(vsmall)) ///
			xlabel(2000 (2) 2011) ///
			note("Sources: ODA, OOF, Private Flows (OECD); Remittances, Tax Revenues (World Bank)" "Note: Tax Revenues from the Central Government and are extrapolated")
		graph export "$graph/ff_odctax.pdf", replace		

*All Developing (and transition) combined		
	
	use "$output\financialflows.dta", clear	

	*create different regional private flow variable
		gen private_reg = private if devstatus==4 //regions
		gen private_ctry = private if devstatus!=4
	*collapse
		collapse (sum) oda oof private* remittances epol_taxr, by(year)
		
	*for stacked area (convert to billions)
		ds year, not
		foreach v in `r(varlist)'{
			replace `v' = `v'/1000
			}
			*end
	*for stacked area
		gen official = oda + oof
			lab var official "ODA and other offical flows"
		gen remit = official + remittances
			lab var remit "Remittances"
		gen priv_ctry = remit + private_ctry 
			lab var priv_ctry "Country Private Flows"
		gen priv_reg = priv_ctry + private_reg
			lab var priv_reg "Regional Private Flows"
		gen rev = priv_reg + epol_taxr
			lab var rev "Tax Revenues"
	*export
		export excel using "$excel\FFgraphs.xlsx", sheet("TotDev") firstrow(variables) sheetreplace
		
	*all developing countries financial flows
		twoway area priv_reg year if year>=2000 & year<=2011, lcolor(navy) fcolor(navy) fintensity(15) || ///
			area priv_ctry year if year>=2000 & year<=2011, lcolor(navy) fcolor(navy) || ///
			area remit year if year>=2000 & year<=2011, lcolor(maroon) fcolor(maroon)|| ///
			area official year if year>=2000 & year<=2011, lcolor(forest_green) fcolor(forest_green) ///
			title("Financial Flows to Developing Countries", position(11)) ///
			sub("in billions of current USD", position(11)) ///
			legend(order( 4 "ODA + OOF" 3 2 1)row(1) size(vsmall)) ///
			xlabel(2000 (2) 2011) ///
			ylabel(0 (300) 900) ///
			note("Sources: ODA, OOF, Private Flows (OECD); Remittances (World Bank)")
		graph export "$graph/ff_all.pdf", replace
		
	*scale to trillions
		foreach v of varlist official remit priv* rev{
			replace `v' = `v'/1000
			}
		*end
		
	*all developing countries financial + tax revenue flows
		twoway area rev year if year>=2000 & year<=2011, lcolor(khaki) fcolor(khaki) || ///
			area priv_reg year if year>=2000 & year<=2011, lcolor(navy) fcolor(navy) fintensity(15) || ///
			area priv_ctry year if year>=2000 & year<=2011, lcolor(navy) fcolor(navy) || ///
			area remit year if year>=2000 & year<=2011, lcolor(maroon) fcolor(maroon)|| ///
			area official year if year>=2000 & year<=2011, lcolor(forest_green) fcolor(forest_green) ///
			title("Financial Flows to Developing Countries", position(11)) ///
			sub("in trillions of current USD", position(11)) ///
			legend(order( 5 "ODA + OOF" 4 1 3 2) row(2) size(vsmall)) ///
			xlabel(2000 (2) 2011) ///
			note("Sources: ODA, OOF, Private Flows (OECD); Remittances, Tax Revenues (World Bank)" "Note: Tax Revenues from the Central Government and are extrapolated")
		graph export "$graph/ff_alltax.pdf", replace



********************************************************************************
********************************************************************************

** REVENUE SHARES (WDI) **

	*open up wdi in stata
		*ssc install wbopendata
		wbopendata, language(en - English) country() topics(13 - Public Sector) indicator() long clear

	*pull out relevant revenue variables
		*ds , has(varlabel "*revenue*" "*Revenue*")  varwidth(20) 
		* interested in breakdown of revenue --> % of revenue (variables)
		ds , has(varlabel "*% of revenue*")  varwidth(20)
		/* revenue variable on interest payment as % of revenue cause %'s 
			to go over 100% so remove this */
		ds `r(varlist)', not(varlab "*Interest*") varwidth(20)

	*create a global macro for revenue % variables
		global revpct `r(varlist)'
		describe $revpct

	*keep just relevant revenue variables 
		keep countryname countrycode region year $revpct
		
	* create a total revenue variable to make sure they add up (close) to 100
		egen totrevpct =  rowtotal($revpct), m
		sum totrevpct, d
		

	*collapse for overall average breakdown in revenue
		*save variable labels
		foreach v of var * {
				local l`v' : variable label `v'
					if `"`l`v''"' == "" {
					local l`v' "`v'"
				}
		}
		*end
		
		collapse (mean) $revpct, by(year)
		
		*re-attach variable labels
			foreach v of var * {
				label var `v' "`l`v''"
			}
			*end
			
	*drop missing data
		drop if year<1990 | year==2014 //no data in collapse
		
	*check total percent (dealing with averages so it wont be perfect	
		egen totrevpct =  rowtotal($revpct), m //tends to be about 5-10% over 100%

	*rename
		rename gc_rev_gotr_zs grants
		rename gc_rev_socl_zs socialconts
		rename gc_tax_gsrv_rv_zs tax_gds
		rename gc_tax_intt_rv_zs tax_trade
		rename gc_tax_othr_rv_zs tax_oth
		rename gc_tax_ypkg_rv_zs tax_inc

	*relabel (removing (% of revenue)
		ds year totrevpct ,not
		foreach i in `r(varlist)' {
			local a : variable label `i'
			local a: subinstr local a " (% of revenue)" ""
			label var `i' "`a'"
			}
			*end
		
	* all flows line graph
		ds year totrevpct,not
		twoway line `r(varlist)' year, legend(size(small)) xlabel(1990 (5) 2013) ///
			ytitle("% of total revenue") title("Average Annual Country Revenue Shares")
	* lumped taxes line graph
		egen tottax = rowtotal(tax_gds tax_trade tax_oth tax_inc)
		twoway connect grants socialconts tottax year, ///
			legend(order (1 "Grants" 2 "Social contributions" 3 "Taxes") rows(1)) ///
			xlabel(1990 (5) 2013) ///
			ytitle("% of total revenue") ///
			title("Average Annual Country Revenue Shares")
		
	*generate stacked variables for stacked area graph
		local stack grants a_socialconts a_tax_gds a_tax_trade a_tax_inc
		local new socialconts tax_gds tax_trade tax_inc tax_oth
		local n: word count `new'	
		forvalues i = 1/`n'{
			local a : word `i' of `stack'
			local b : word `i' of `new'
			gen a_`b' = `b' + `a'
			local label : variable label `b'		
				lab var a_`b' "`label'"
			}
			*end
		
	*stacked area		
		twoway area a_tax_oth a_tax_inc a_tax_trade a_tax_gds a_socialconts grants year, ///
			title("Average Annual Country Revenue Shares") ///
			ytitle("% of total revenue") ///
			ylabel(0 (20) 120) ///
			xlabel(1990 (5) 2013) ///
			legend(off) /// legend(order(6 5 4 3 2 1) size(small))
			text(10 1994 "Grants/other revenue") ///
			text(32 1994 "Social contributions") ///
			text(55 1994 "Taxes: goods/services") ///
			text(76 1994 "Taxes: internat'l trade") ///
			text(95 1996 "Taxes: income, profits, capital gains") ///
			text(113 1993 "Taxes: other") 
			
	*stacked area (taxes all shaded the same color)		
		twoway area a_tax_oth a_socialconts grants year || ///  
			line a_tax_inc year, lcolor(white) || ///
			line a_tax_trade year, lcolor(white) || ///
			line a_tax_gds year, lcolor(white) ///
			title("Average Annual Country Revenue Shares") ///
			ytitle("% of total revenue") ///
			lcolor(white) ///
			ylabel(0 (20) 120) ///
			xlabel(1990 (5) 2013) ///
			legend(off) /// legend(order(6 5 4 3 2 1) size(small))
			text(10 1994 "Grants/other revenue") ///
			text(32 1994 "Social contributions") ///
			text(55 1994 "Taxes: goods/services") ///
			text(75 1994 "Taxes: internat'l trade") ///
			text(95 1996 "Taxes: income, profits, capital gains") ///
			text(113 1993 "Taxes: other") ///
			note("Note: Total will be greater than 100 percent due to working with annual country average shares" ///
				"Source: World Bank WDI") 
		graph export "$graph/ff_revshares.pdf", replace

********************************************************************************
********************************************************************************

** EXPORT ADDITIONAL DATA FOR FIGURES **

*1b
	use "$output\financialflows.dta", clear	

	*generate real flows
		foreach f in oda oof  private remittances{
			replace `f' = `f'/1000 //convert to billions
			gen real_`f' = `f'/cpi_d // in billions
	
			}	
			*end

	*collapse
		collapse (sum) oda oof remittances private real_* population, by(year)
	
	* generate offical
		gen official = oda + oof
			lab var official "ODA and other offical flows"
		gen real_official = real_oda + real_oof
	* generate real per capita
		foreach f in official private remittances{
			gen realpc_`f' = (real_`f'*1000)/population 
			}
			*end
			
	*export
		export excel using "$excel\FFgraphsforPaper.xlsx", sheet("TotDevReal") firstrow(variables) sheetreplace

* Fragility

	use "$output\financialflows_const.dta", clear	
	
	local count = 1
	foreach x in "fragile==2" "fragile!=2"{
		preserve
		*collapse
			collapse (sum) oda oof remittances private population if `x', by(year)
		
		*generate offical flows
			gen official = oda + oof
				lab var official "ODA and other offical flows"
		
		*generate real flows
			foreach f in oda oof official private remittances{
				replace `f' = `f'/1000 //convert to billions
				}	
				*end
		*export
			local ffex `"export excel using "$excel\FFgraphs.xlsx", firstrow(variables) sheetreplace"'
			if `count' == 1 `ffex' sheet("Fragile")
			else `ffex' sheet("NonFragile")
		restore
		local count = `count' + 1 
			}
			*end

*Resource Dependence
	
	use "$output\financialflows.dta", clear
	
	*data availablity
		table year, c(n tot_resource_rev n tot_nresource_rev_inc_sc n social_contrib n grants)
		
	*countries where resource revenue is great than non resource revenue
		tab ctry if ///
			trv_tot_resource_rev>trv_tot_nresource_rev_inc_sc & ///
			trv_tot_resource_rev!=. & ///
			year>=1995
	*countries, years and amts where resource revenue is great than non resource revenue
		list ctry year  tot_resource_rev tot_nresource_rev_inc_sc if ///
			trv_tot_resource_rev>trv_tot_nresource_rev_inc_sc & ///
			trv_tot_resource_rev!=. & ///
			year>=1995

	*Financial flows total (to compare to revenue) 
		* only countries with revenue
		egen id = group(ctry year) 
		bysort id: egen tot_flows = total(oda + oof + remittances + private) if trv_tot_nresource_rev_inc_sc!=.
		drop id
		
	*export		
		local count = 1
		foreach x in "resdep==2" "resdep!=2"{
		preserve
		*collapse
			collapse (sum) trv_tot_resource_rev trv_tot_nresource_rev_inc_sc trv_social_contrib trv_grants tot_flows if `x', by(year)
		
		*generate real flows
			foreach f in trv_tot_resource_rev trv_tot_nresource_rev_inc_sc trv_social_contrib trv_grants tot_flows{
				replace `f' = `f'/1000 //convert to billions
				}	
				*end
				
		*export
			local ffex `"export excel using "$excel\FFgraphs.xlsx", firstrow(variables) sheetreplace"'
			if `count' == 1 `ffex' sheet("ResourceDep")
			else `ffex' sheet("NonResDep")
		restore
		local count = `count' + 1 
			}
			*end

	
*Resource Revenue Constant Sample
	*indentify a constant sample for resource dependence
	*(full obseravtions for all years and flows)
	
		table year, c(n trv_tot_resource_rev n trv_tot_nresource_rev_inc_sc n trv_social_contrib)
		
		*identify country with all flows in a given year
			egen flowmisscount = rowmiss(trv_tot_resource_rev trv_tot_nresource_rev_inc_sc trv_social_contrib)
				gen full = 2 if flowmisscount==0
				replace full = 1 if flowmisscount!=0
					drop flowmisscount
				lab var full "Country has all flows for given year"
				lab val full yn
				*observation per year
					tab year if full==2
				
		*identify countries with all flows for full time period
			foreach pdstart of numlist 1980/2010{
				preserve
				qui: drop if year>2010 //no observations after 2010
				qui: drop if year<`pdstart'
				qui: bysort ctry: egen bookends = min(full) if inlist(year, `pdstart', 2010) // do countries have a full set of flows in 2000 and 2012?
				qui: lab val bookends yn
				qui: sum bookends if year==2010 & bookends==2
				if `pdstart'==1980 di "     How many countries have full datasets with different starting years?" ///
					_newline "       YEAR      # COUNTRIES"
				di "       `pdstart'            `r(N)'"
				restore
				}
				*end
				
		/* identify all countries that have the same start and end year and
		interpolate any missing values in between */
		bysort ctry: egen bookends = min(full) if inlist(year, 2002, 2010) // do countries have a full set of flows in 2000 and 2010?
		bysort ctry: egen include = min(bookends) // project bookends onto rest of years for country
			lab val bookends include yn
		
		*keep countries that have observations at both ends of range 
			keep if include==2
			keep if year>=2002 & year<=2010
			tab ctry if year==2010 //86 countries in constant sample
			bysort ldc: sum ctry if year==2010
			bysort resdep: sum ctry if year==2010
		
		*interpolate between endpoints
			sort ctry year
			rename trv_tot_nresource_rev_inc_sc trv_tot_nresource_rev
			foreach v of varlist trv_tot_resource_rev trv_tot_nresource_rev trv_social_contrib trv_grants{
				by ctry: ipolate `v' year, gen(epol_`v') epolate
					local label : variable label `v'		
					lab var epol_`v' "Extrapolated `label'"
				}
				*end
		*drop extra variables	
			drop full bookends include
		
		*Financial flows total (to compare to revenue) 
		* only countries with revenue
			drop tot_flows id
			egen id = group(ctry year) 
			bysort id: egen tot_flows = total(oda + oof + remittances + private) if epol_trv_tot_nresource_rev!=.
			drop id
		
		*export		
			local count = 1
			foreach x in "resdep==2" "resdep!=2"{
			preserve
			*collapse
				collapse (sum) epol_trv* tot_flows if `x', by(year)
			
			*generate real flows
				foreach f in epol_trv_tot_resource_rev epol_trv_tot_nresource_rev epol_trv_social_contrib epol_trv_grants tot_flows{
					replace `f' = `f'/1000 //convert to billions
					}	
					*end
					
			*export
				local ffex `"export excel using "$excel\FFgraphs.xlsx", firstrow(variables) sheetreplace"'
				if `count' == 1 `ffex' sheet("ConstResDep")
				else `ffex' sheet("ConstNonResDep")
			restore
			local count = `count' + 1 
				}
				*end

				
*Resource Revenue Average, Aggregate Level (2008-2010)
	
	use "$output\financialflows.dta", clear

	* indentify a constant sample for resource dependence
	*(full obseravtions for all years and flows)
	
		table year, c(n trv_tot_resource_rev n trv_tot_nresource_rev_inc_sc n trv_social_contrib)
		
		*identify country with all flows in a given year
			egen flowmisscount = rowmiss(trv_tot_resource_rev trv_tot_nresource_rev_inc_sc trv_social_contrib)
				gen full = 2 if flowmisscount==0
				replace full = 1 if flowmisscount!=0
					drop flowmisscount
				lab var full "Country has all flows for given year"
				lab val full yn
				
		/* identify all countries that have the same start and end year and
		interpolate any missing values in between */
		bysort ctry: egen bookends = min(full) if inlist(year, 2008, 2010) // do countries have a full set of flows in 2008 and 2010?
		bysort ctry: egen include = min(bookends) // project bookends onto rest of years for country
			lab val bookends include yn
		
		*keep countries that have observations at both ends of range 
			keep if include==2
			keep if year>=2008 & year<=2010
			bysort resdep: tab ctry if year==2010 //15 countries in constant sample
			bysort ldc: sum ctry if year==2010
			bysort resdep: sum ctry if year==2010
		
		*interpolate between endpoints
			sort ctry year
			rename trv_tot_nresource_rev_inc_sc trv_tot_nresource_rev
			foreach v of varlist trv_tot_resource_rev trv_tot_nresource_rev trv_social_contrib trv_grants{
				by ctry: ipolate `v' year, gen(epol_`v') epolate
					local label : variable label `v'		
					lab var epol_`v' "Extrapolated `label'"
				}
				*end
				
		*drop extra variables	
			drop full bookends include
			
	*avg pd between 2008-2010
		drop if year<2008 | year>2010
		local val epol_trv_tot_resource_rev epol_trv_tot_nresource_rev epol_trv_social_contrib epol_trv_grants
		foreach f in `val' {
			by ctry: egen avg_`f' = mean(`f')
			lab var avg_`f' `"Avg `=proper("`f'")' Flows (2008-2010)"'
			}
			*end
	*keep if year
		keep if year==2010
		
	collapse (mean) avg_*, by(resdep)
	
	*export		
		export excel using "$excel\FFgraphs.xlsx", firstrow(variables) sheetreplace sheet("ConstAvgResDep")


*Resource Revenue Average Resource Revenues with CONSTANT SAMPLE (2008-2010)
	
	use "$output\financialflows_const.dta", clear

	* indentify a constant sample for resource dependence
	*(full obseravtions for all years and flows)
	
		table year, c(n trv_tot_resource_rev n trv_tot_nresource_rev_inc_sc n trv_social_contrib)
		
		*identify country with all flows in a given year
			egen flowmisscount = rowmiss(trv_tot_resource_rev trv_tot_nresource_rev_inc_sc trv_social_contrib)
				gen full = 2 if flowmisscount==0
				replace full = 1 if flowmisscount!=0
					drop flowmisscount
				lab var full "Country has all flows for given year"
				lab val full yn
				
		/* identify all countries that have the same start and end year and
		interpolate any missing values in between */
		bysort ctry: egen bookends = min(full) if inlist(year, 2008, 2010) // do countries have a full set of flows in 2008 and 2010?
		bysort ctry: egen include = min(bookends) // project bookends onto rest of years for country
			lab val bookends include yn
		
		*keep countries that have observations at both ends of range 
			keep if include==2
			keep if year>=2008 & year<=2010
			bysort resdep: tab ctry if year==2010 //15 countries in constant sample
			bysort ldc: sum ctry if year==2010
			bysort resdep: sum ctry if year==2010
		
		*interpolate between endpoints
			sort ctry year
			rename trv_tot_nresource_rev_inc_sc trv_tot_nresource_rev
			foreach v of varlist trv_tot_resource_rev trv_tot_nresource_rev trv_social_contrib trv_grants{
				by ctry: ipolate `v' year, gen(epol_`v') epolate
					local label : variable label `v'		
					lab var epol_`v' "Extrapolated `label'"
				}
				*end
				
		*drop extra variables	
			drop full bookends include
			
	*gen official
		gen epol_official = epol_oda + epol_oof
			lab var epol_official "ODA and other offical flows"
			
	*avg pd between 2008-2010
		drop if year<2008 | year>2010
		local tax epol_trv_tot_resource_rev epol_trv_tot_nresource_rev epol_trv_social_contrib epol_trv_grants
		local flows epol_official epol_private epol_remittances
		foreach f in `tax' `flows' {
			by ctry: egen avg_`f' = mean(`f')
			lab var avg_`f' `"Avg `=proper("`f'")' Flows (2008-2010)"'
			}
			*end
	*keep if year
		keep if year==2010
		
	collapse (mean) avg_*, by(resdep)
	
	*export		
		export excel using "$excel\FFgraphs.xlsx", firstrow(variables) sheetreplace sheet("ConstAvgResDep")

		
*Country Level and Aggregate Average Growth Rates
	
	use "$output\financialflows_const.dta", clear
			
	*create total flow
		qui: gen epol_totflow = epol_oda + epol_oof + epol_private + epol_remittances
		lab var epol_totflow "Total Financial Flows"
	
	*gen official
		gen epol_official = epol_oda + epol_oof
			lab var epol_official "ODA and other offical flows"		
	
	*create various flows
		foreach f in totflow official private remittances{
			* per capita flows
				*gen pc_`f' = epol_`f'/population
				*lab var pc_`f' "`=proper("`f'")' Flows per capita"
			* real flows, total
				gen real_`f' = epol_`f'/cpi_d
				lab var real_`f' "`=proper("`f'")' Flows in real terms"
			* real flows per capita
				*gen realpc_`f' = real_`f'/population
				*lab var realpc_`f' "`=proper("`f'")' Mean Flows per capita in real terms"
			*share of total
				gen sh_`f' = (real_`f'/real_totflow)*100
				lab var sh_`f' "Country share of `=proper("`f'")' flows in real terms"
			*growth rate
				gen base95 = sh_`f' if year==1995
				bysort ctry: egen flowbase = min(base95)
				qui: gen sh_gr_`f' = (sh_`f'/flowbase)-1
				lab var sh_gr_`f' "Country growth rate in share of `=proper("`f'")' flows since 1995"
				drop base95 flowbase
			}
			*end
			
	/*country level average growth
		foreach t in "epol_" "real_" "realpc_"{
			foreach f in official private remittances{
				qui: gen base95 = `t'`f' if year==1995
				bysort ctry: egen flowbase = min(base95)
				qui: gen `t'`f'_gr = (`t'`f'/flowbase)-1
				drop base95 flowbase
				}
			}
			*end			
	*/
	
	*collapse
		collapse (mean) real_* sh_gr_*, by(year)
	
	*create aggregate growth rate in share of avg
		foreach f in totflow official private remittances{
			*share of total
				gen agsh_`f' = (real_`f'/real_totflow)*100
				lab var agsh_`f' "Agg avg share of `=proper("`f'")' flows in real terms"
			*growth rate
				gen base95 = agsh_`f' if year==1995
				egen flowbase = min(base95)
				qui: gen agsh_gr_`f' = (agsh_`f'/flowbase)-1
				lab var agsh_gr_`f' "Agg avg growth rate in share of `=proper("`f'")' flows since 1995"
				drop base95 flowbase
		}
		*end
		
	*export
		export excel year *_gr_* using "$excel\FFgraphs.xlsx", firstrow(variables) sheetreplace sheet("ConstAvgCtryGR")



* Real Avg Resource Dependence Flows (2006-2010)
		
	use "$output\financialflows_const.dta", clear

	* indentify a constant sample for resource dependence
	*(full obseravtions for all years and flows)
	
		keep if year>=2006 & year<=2010
		
		table year, c(n trv_tot_resource_rev n trv_tot_nresource_rev_inc_sc n trv_social_contrib)
		
		tab nresdep year, m // 78 countries (342 not, 48 yes over 5 years)
		
		*identify country with all flows in a given year
			*egen flowmisscount = rowmiss(trv_tot_resource_rev trv_tot_nresource_rev_inc_sc trv_social_contrib)
			*drop if flowmisscount==3 //no flows in a given year
			*drop flowmisscount
		
		*gen official
			gen epol_official = epol_oda + epol_oof
			lab var epol_official "ODA and other offical flows"
			
		*gen totflow
			gen totflow = trv_tot_resource_rev + trv_tot_nresource_rev_inc_sc + epol_official + epol_remittances + epol_private
		
		*keep only full series (drop if rev data is missing)
			drop if totflow==.
			unique ctry, by(nresdep) gen(unique) //15 no, 9 yes
				drop unique
				
		*rename (due to length)
			rename trv_tot_nresource_rev_inc_sc trv_tot_nresource_rev
			
		*convert to real
			foreach f in trv_tot_resource_rev trv_tot_nresource_rev epol_official epol_remittances epol_private totflow{
				gen r_`f' = `f'/cpi_d
			}
			*end
			
		*share of total at country level (unweighted average)
			ds r_*
			foreach f in `r(varlist)'{
				gen sh_`f' = `f'/r_totflow
				}
				*end
			
		*identify averages
			local rev r_trv_tot_resource_rev r_trv_tot_nresource_rev
			local flows r_epol_official r_epol_private r_epol_remittances
			local shares sh_r_trv_tot_resource_rev sh_r_trv_tot_nresource_rev sh_r_epol_official sh_r_epol_remittances sh_r_epol_private
			/*foreach f in `rev' `flows'{
				bysort ctry: egen avg_`f' = mean(`f')
				}
				*end
			*/
		
		*collapse
			collapse `rev' `flows' `shares', by(nresdep)
			*collapse avg_*, by(resdep)
			
	*export		
		export excel using "$excel\FFgraphs.xlsx", firstrow(variables) sheetreplace sheet("ConstAvgResDep2")



* Long Run Average Composition
	
	use "$output\financialflows_const.dta", clear

	*Avg over 2008-2012 (keep obs in timeframe)
		keep if year>=2008 & year<=2012
				
	*create variable - official flows
		gen epol_official = epol_oda + epol_oof
		lab var epol_official "ODA and other offical flows"
			
	*create variable - total flows
		gen totflow = epol_official + epol_remittances + epol_private
		
	*convert to share of total at country level (unweighted average)
		foreach f in epol_official epol_remittances epol_private {
			gen sh_`f' = `f'/totflow
		}

	*locals for collpase
		local flows epol_official epol_private epol_remittances totflow
		local shares sh_epol_official sh_epol_remittances sh_epol_private
		
	*collapse
		collapse (sum)`flows' (mean) `shares', by(ldc year)
		ds epol_* totflow
		foreach v in `r(varlist)'{
			replace `v' = `v'/1000
			}
		collapse `flows' `shares', by(ldc)
			
	*export		
		export excel using "$excel\FFgraphs.xlsx", firstrow(variables) sheetreplace sheet("ConstLAvgLDCs")
