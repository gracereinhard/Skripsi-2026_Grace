* Grace Reinhardinanti Dee Caksono
* 2206038574
* Data Run #7

* ------------- 0. ENVIRONMENT SETUP
clear all
set more off
capture log close

* Set Working Directory
global input_dir "/Users/gracereinhard/Documents/Skripsi/Skripsi 2026_Grace/STATA/Cleaned Data"

global working_dir "/Users/gracereinhard/Documents/Skripsi/Skripsi 2026_Grace/STATA/Working Data"

global output_dir "/Users/gracereinhard/Documents/Skripsi/Skripsi 2026_Grace/STATA/Output Data"

**# Energy Intensity (Y)
* ------------- 1. FORMING THE DEPENDENT VARIABLE (Y)
import excel "$input_dir/Master_VA_Output_Real.xlsx", sheet("Sheet 1") firstrow clear

* Remove energy production sectors (c8 and c17) from the proportion calculation
drop if Sector_Code == "c8" | Sector_Code == "c17"

* Calculate Industrial Output Proportions
** Calculate Total Output for remaining industries (c2-c18 excluding c8/c17) per Country-Year
bysort Year Country: egen Total_Industry_Out_ADB = sum(r69_Total_Output)
** Calculate output share for each sector
gen proportion = r69_Total_Output / Total_Industry_Out_ADB
** Save temporary dataset for merging
save "$working_dir/ADB_Ready.dta", replace

* Merge with APEC Data and Estimate Consumption
** Load APEC Data (Aggregate Industrial Energy)
import excel "$input_dir/Master_APEC_Energy.xlsx", firstrow clear
save "$working_dir/APEC_Master_Data.dta", replace
use "$working_dir/APEC_Master_Data.dta", clear
** Merge: One APEC row (Year-Country) to Many ADB rows (Sectors)
merge 1:m Year Country using "$working_dir/ADB_Ready.dta"

* Generate Dependent Variables
** Estimate Sectoral Energy Consumption: APEC Total Energy * ADB Output Share
gen Sector_Energy = Total_Energy_Industry * proportion
** Calculate Energy Intensity (EI): Energy / Real Value Added
gen EI = Sector_Energy / r64_Value_Added
** Transform to Logarithm (Natural Log)
gen lnEI = ln(EI)

* Cleanup and Sort
** Remove intermediate variables and unmerged observations
drop Total_Energy_Industry Total_National Electricity_Plants ///
     Oil_Refineries r64_Value_Added r69_Total_Output ///
     Total_Industry_Out_ADB proportion _merge
** Filter for target countries only
keep if inlist(Country, "INO", "MAL", "PHI", "THA", "VIE")
** Sort data hierarchically: Year > Country > Sector (Numeric)
gen sector_num = real(substr(Sector_Code, 2, .))
sort Year Country sector_num
drop sector_num
drop if Year == 2007
** Save Final Dependent Variable Dataset
save "$working_dir/Database_Final_Y.dta", replace

**# Vertical Energy Spillover (S_EI)
* ------------- 2. FORMING INDEPENDENT VARIABLE (X): VERTICAL ENERGY SPILLOVERS (S_EI)
*** PART A: PREPARING EI SUPPLIER DATA ***
* Import ADB Data
import excel "$input_dir/Master_VA_Output_Real.xlsx", sheet("Sheet 1") firstrow clear

* Flag Energy Sectors
** Create binary flag for energy sectors (c8 = Oil Refining, c17 = Electricity)
gen is_energy_sector = (Sector_Code == "c8" | Sector_Code == "c17")

* Calculate Proportions for Non-Energy Sectors
** Calculate denominator only for standard industries (is_energy_sector == 0)
bysort Year Country: egen Total_Industry_Out = sum(r69_Total_Output) if is_energy_sector == 0
** Generate proportion variable
gen prop_industry = r69_Total_Output / Total_Industry_Out if is_energy_sector == 0

* Merge with APEC Data
** Merge Many-to-One: Many ADB sectors match to one APEC Country-Year entry
merge m:1 Year Country using "$working_dir/APEC_Master_Data.dta"
** Keep only matched observations
drop if _merge == 2
drop _merge

* Generate Hybrid Sectoral Energy (Energy_Final)
gen Energy_Final = .

* Approach 1: Standard Manufacturing (c2-c18 excluding c8/c17)
* Use calculated proportions derived from APEC "Total Industry" line
replace Energy_Final = prop_industry * Total_Energy_Industry if is_energy_sector == 0

* Approach 2: Electricity Sector (c17)
* Direct assignment from APEC specific line item
replace Energy_Final = Electricity_Plants if Sector_Code == "c17"

* Approach 3: Oil Refining Sector (c8)
* Direct assignment from APEC specific line item
replace Energy_Final = Oil_Refineries if Sector_Code == "c8"

* Calculate Supplier Energy Intensity (EI_supplier)
** Formula: Hybrid Energy / Real Value Added
gen EI_supplier = Energy_Final / r64_Value_Added

* Final Cleanup and Save
keep Year Country Sector_Code EI_supplier
** Sort data hierarchically: Year > Country > Sector (Numeric)
gen sector_num = real(substr(Sector_Code, 2, .))
sort Year Country sector_num
drop sector_num

** Save Final Independent Variable Dataset
save "$working_dir/Database_EI_Supplier_Final.dta", replace

*** PART B: CALCULATING S_EI ***
* Load Weights Data
use "$input_dir/Master_Weights_2008_2022.dta", clear

* Parse Buyer ID
gen Buyer_Country = substr(buyer_id, 1, 3)
gen Buyer_Sector  = substr(buyer_id, 5, .)

* Parse Supplier ID
gen Supplier_Country = substr(supplier_id, 1, 3)
gen Supplier_Sector  = substr(supplier_id, 5, .)

* Prepare for Merge
rename Supplier_Country Country
rename Supplier_Sector  Sector_Code
rename year Year

* Merge with Supplier EI Database
merge m:1 Year Country Sector_Code using "$working_dir/Database_EI_Supplier_Final.dta"
drop if _merge == 2

* Exclude intra-industry linkages (self-spillovers) to avoid reflection bias
drop if supplier_id == buyer_id

* Handle missing EI data
replace EI_supplier = 0 if _merge == 1
drop _merge

* Calculate Spillover Component
gen spill_component = 0
replace spill_component = weight * ln(EI_supplier) if EI_supplier > 0

* Aggregation (Collapse)
collapse (sum) S_EI = spill_component, by(Year Buyer_Country Buyer_Sector)

* Final Formatting
rename Buyer_Country Country
rename Buyer_Sector  Sector_Code
gen sector_num = real(substr(Sector_Code, 2, .))
sort Year Country sector_num
drop sector_num

save "$working_dir/Database_Spillover_EI.dta", replace

**# Tech Spillovers (S_T)
* ------------- 3. FORMING INDEPENDENT VARIABLE (X): TECH SPILLOVERS (S_T)
*** PART A: Prepare Tech Shocks (Supplier Nominal Output) ***
import excel "$input_dir/Master_VA_Output_Real.xlsx", sheet("Sheet 1") firstrow clear

* Identify Tech Leaders in High-Tech Sectors
gen is_tech_leader = inlist(Country, "AUS", "CAN", "PRC", "JPN", "KOR", "MEX", "USA", "TAP", "SIN") | ///
                     inlist(Country, "GER", "FRA", "UKG", "ITA")

gen is_high_tech   = inlist(Sector_Code, "c9", "c13", "c14", "c15")
keep if is_tech_leader == 1 & is_high_tech == 1

rename r69_Total_Output Tech_Output_Shock
keep Year Country Sector_Code Tech_Output_Shock
save "$working_dir/Tech_Capacity_Shocks.dta", replace

*** PART B: Calculate S_Tech using ln(Shock) ***
use "$input_dir/Master_Weights_2008_2022.dta", clear

* Split IDs for merging
split supplier_id, p("_") gen(s)
rename s1 Country
rename s2 Sector_Code
rename year Year

* Merge with Nominal Output Shock 
merge m:1 Year Country Sector_Code using "$working_dir/Tech_Capacity_Shocks.dta"
replace Tech_Output_Shock = 0 if _merge != 3
drop _merge

* Exclude intra-industry self-spillovers (jika supplier_id sama dengan buyer_id)
drop if supplier_id == buyer_id

* Formula: Weight_t * ln(Supplier_Output_t)
gen tech_comp = weight * ln(Tech_Output_Shock) if Tech_Output_Shock > 0

* Aggregate for Buyer
split buyer_id, p("_") gen(b)
collapse (sum) S_Tech = tech_comp, by(Year b1 b2)

rename b1 Country
rename b2 Sector_Code

save "$working_dir/Database_Spillover_Tech.dta", replace

**# Value Added per Output (VA/O)
* ------------- 4. FORMING CONTROL VARIABLE: Value Added per Output (VA/O)
* Value Added per Output (VA/O)
import excel "$input_dir/Master_VA_Output_Real.xlsx", sheet("Sheet 1") firstrow clear

* Formula: Real Value Added / Real Total Output
gen VA_per_Output = r64_Value_Added / r69_Total_Output

keep Year Country Sector_Code VA_per_Output
save "$working_dir/Control_VAO.dta", replace

**# Energy Price Ratio (ln(Pe/Pq))
* ------------- 5. FORMING CONTROL VARIABLE: Energy Price Ratio (ln(Pe/Pq))
*** PART A: Create Sectoral Deflator (Pq) from Output Files ***
* Load Real Output (The Denominator)
import excel "$input_dir/Master_VA_Output_Real.xlsx", sheet("Sheet 1") firstrow clear
rename r69_Total_Output Output_Real
keep Year Country Sector_Code Output_Real
save "$working_dir/Temp_Real_Output.dta", replace

* Load Nominal Output (The Numerator)
import excel "$input_dir/Master_VA_Output_Nominal.xlsx", sheet("Sheet 1") firstrow clear
rename r69_Total_Output Output_Nom
keep Year Country Sector_Code Output_Nom

* Merge to calculate Deflator
merge 1:1 Year Country Sector_Code using "$working_dir/Temp_Real_Output.dta"
keep if _merge == 3
drop _merge

* Calculate Sectoral Deflator (Nominal / Real)
destring Output_Nom Output_Real, replace force
gen Pq_Sectoral = Output_Nom / Output_Real

* Clean up for merging
keep Year Country Sector_Code Pq_Sectoral
save "$working_dir/Temp_Sectoral_Deflator.dta", replace

*** PART B: Prepare Energy Expenditure (Nominal Pe Numerator) ***
import excel "$input_dir/Master_Energy_Exp.xlsx", firstrow clear

destring Year, replace

* Ensure consistent naming
capture rename Total_Energy_Exp Energy_Exp_USD

save "$working_dir/Energy_Exp_Temp.dta", replace

*** PART C: Combine to Calculate Final Price Ratio ***
use "$working_dir/Energy_Exp_Temp.dta", clear

* Merge Physical Energy (to get Unit Price Pe)
merge 1:1 Year Country Sector_Code using "$working_dir/Database_Final_Y.dta", keepusing(Sector_Energy)
** Keep only if we have both Expenditure data AND Quantity data
keep if _merge == 3
drop _merge

* Merge Sectoral Deflator (Pq)
merge 1:1 Year Country Sector_Code using "$working_dir/Temp_Sectoral_Deflator.dta"
keep if _merge == 3
drop _merge

*** PART D: Calculate Relative Price ***
* Calculate Nominal Price of Energy (Pe)
** Price = Total Expenditure / Total Physical Units
gen Pe_Nominal = Energy_Exp_USD / Sector_Energy

* Calculate Real Relative Price
** Real Price = Nominal Price / Sectoral Deflator
gen Energy_Price = Pe_Nominal / Pq_Sectoral

* Take the Natural Log (for elasticity interpretation)
gen ln_Energy_Price = ln(Energy_Price)

keep Year Country Sector_Code ln_Energy_Price

*** PART E: SORTING AND CLEANING UP ***
gen sector_num = real(substr(Sector_Code, 2, .))
sort Year Country sector_num
drop sector_num

save "$working_dir/Control_Energy_Price.dta", replace

**# Service Share & Import Share
* ------------- 6. FORMING CONTROL VARIABLE: Service Share & Import Share
* Load weights data
use "$input_dir/Master_Weights_2008_2022.dta", clear
split supplier_id, p("_") gen(s)
split buyer_id, p("_") gen(b)

rename s1 Supplier_Country
rename s2 Supplier_Sector
rename b1 Buyer_Country
rename b2 Buyer_Sector

* Identify International Imports
** Logic: If the country selling is NOT the country buying, it is an import.
gen is_import = (Supplier_Country != Buyer_Country)

* Identify Service Inputs
** Logic: In ADB MRIO, sectors c19 to c35 are Services.
gen s_num = real(substr(Supplier_Sector, 2, .))
gen is_service = (s_num >= 19 & s_num <= 35)

* Calculate the Share of TOTAL OUTPUT (r69)
* Because 'weight' is already (Flow / r69), the sum of weights is the Total Share.
bysort year Buyer_Country Buyer_Sector: egen imp_share_temp = sum(weight) if is_import == 1
bysort year Buyer_Country Buyer_Sector: egen ser_share_temp = sum(weight) if is_service == 1

* Collapse to get one clean row per Industry-Year
collapse (max) Import_Share = imp_share_temp Service_Share = ser_share_temp, ///
    by(year Buyer_Country Buyer_Sector)

* Handle industries with 0 imports or 0 services
replace Import_Share = 0 if Import_Share == .
replace Service_Share = 0 if Service_Share == .

* Clean up names for the merge
rename year Year
rename Buyer_Country Country
rename Buyer_Sector Sector_Code

* 8. Check your new Means (They should be between 0 and 1)
summarize Import_Share Service_Share

save "$working_dir/Control_Trade_Service_FINAL.dta", replace

**# Initial Merge
* ------------- 7. THE FINAL MERGE
use "$working_dir/Database_Final_Y.dta", clear

* Merge Energy Spillovers (X1)
merge 1:1 Year Country Sector_Code using "$working_dir/Database_Spillover_EI.dta"
drop if _merge == 2
drop _merge

* Merge Tech Spillovers (X2)
merge 1:1 Year Country Sector_Code using "$working_dir/Database_Spillover_Tech.dta"
drop if _merge == 2
drop _merge

* Merge Control: VA/Output
merge 1:1 Year Country Sector_Code using "$working_dir/Control_VAO.dta"
drop if _merge == 2
drop _merge

* Merge Control: Price Ratio
merge 1:1 Year Country Sector_Code using "$working_dir/Control_Energy_Price.dta"
drop if _merge == 2
drop _merge

* Merge Control: Trade & Services
merge 1:1 Year Country Sector_Code using "$working_dir/Control_Trade_Service_FINAL.dta"
drop if _merge == 2
drop _merge

* Final Data Cleaning
* Drop non-manufacturing sectors (Mining c2, Utilities c17/c18)
drop if Sector_Code == "c2" | Sector_Code == "c18"
drop if Year == 2007

* Panel Data Setup
egen country_id = group(Country)
egen sector_id = group(Sector_Code)
egen industry_id = group(Country Sector_Code)

xtset industry_id Year

* Fill missing controls with 0
replace Import_Share = 0 if Import_Share == .
replace Service_Share = 0 if Service_Share == .

* Quick Check
describe
summarize

save "$working_dir/FINAL_DATA_REGRESSION.dta", replace

**# Descriptive Statistics
* ------------- 8. DESCRIPTIVE STATISTICS
* Prepare Variables and Labels
capture gen Energy_Price = exp(ln_Energy_Price)

label variable EI "Energy Intensity (Raw)"
label variable lnEI "ln(Energy Intensity)"
label variable S_EI "Energy Spillover"
label variable S_Tech "Tech Spillover"
label variable VA_per_Output "Value Added / Output"
label variable Energy_Price "Relative Energy Price (Raw)"
label variable ln_Energy_Price "Relative Energy Price (ln)"
label variable Service_Share "Service Share"
label variable Import_Share "Import Share"

**# Summary Statistics (Aggregate)
* Summary statistics table (aggregate)
estpost summarize EI lnEI S_EI S_Tech VA_per_Output Energy_Price ln_Energy_Price Service_Share Import_Share, listwise

esttab . using "$output_dir/Table_Summary_Aggregate.rtf", ///
    replace label ///
    title("Table 1: Summary Statistics for ASEAN-5 Manufacturing (2008-2022)") ///
    cells("mean(fmt(3)) sd(fmt(3)) min(fmt(3)) max(fmt(3)) count(fmt(0))") ///
    nonumber nomti ///
    collabels("Mean" "Std. Dev." "Min" "Max" "Obs") ///
    addnotes("Note: Energy Intensity is measured in TJ per Million USD." "Sectors: c3-c16 excluding c8. Countries: INO, MAL, PHI, THA, VIE.")
	
shell open "$output_dir/Table_Summary_Aggregate.rtf"

**# Summary Statistics (By Country)
* Summary statistics per country
local countries "INO MAL PHI THA VIE"
local first_time = 1

foreach c in `countries' {
    
    if "`c'" == "INO" local cname "Indonesia"
    if "`c'" == "MAL" local cname "Malaysia"
    if "`c'" == "PHI" local cname "Philippines"
    if "`c'" == "THA" local cname "Thailand"
    if "`c'" == "VIE" local cname "Vietnam"

    * Post stats including both raw VA/O and its log
    estpost summarize EI lnEI S_EI S_Tech VA_per_Output Energy_Price ln_Energy_Price Service_Share Import_Share if Country == "`c'"
    
    local action = cond(`first_time' == 1, "replace", "append")
    
    esttab . using "$output_dir/Table_Full_Stats_by_Country.rtf", ///
        `action' label ///
        title("Summary Statistics: `cname'") ///
        cells("mean(fmt(3)) sd(fmt(3)) min(fmt(3)) max(fmt(3)) count(fmt(0))") ///
        nonumber nomti ///
        collabels("Mean" "Std. Dev." "Min" "Max" "Obs")
    
    local first_time = 0
}

shell open "$output_dir/Table_Full_Stats_by_Country.rtf"

**# Correlation Matrix
* Correlation Matrix
pwcorr lnEI S_EI S_Tech ln_Energy_Price Service_Share Import_Share, star(0.05)

estpost correlate lnEI S_EI S_Tech ln_Energy_Price Service_Share Import_Share, matrix listwise

esttab using "$output_dir/Table2_Correlation_Matrix.rtf", ///
    replace label ///
    title("Table 2: Correlation Matrix of Variables") ///
    unstack not noobs compress ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    b(3)

shell open "$output_dir/Table2_Correlation_Matrix.rtf"

**# Initial Regression
* ------------- 9. INITIAL REGRESSION CHECKS (OLS/FE Only)
* Initial check
xtreg lnEI S_EI S_Tech VA_per_Output Service_Share Import_Share ln_Energy_Price, fe

* Preliminary: Ensure Year Dummies exist
capture drop yr_dummy*
tabulate Year, gen(yr_dummy)

* Run the baseline model
xtreg lnEI S_EI S_Tech VA_per_Output Service_Share Import_Share ln_Energy_Price yr_dummy2-yr_dummy15, fe vce(cluster industry_id)

* Add FE indicators for the table footer
estadd local industry_fe "x"
estadd local year_fe "x"

* Store the results
estimates store fe_baseline

* --- 3. EXPORT THE TABLE TO WORD (.RTF) ---
esttab fe_baseline using "$output_dir/Table3_Baseline_FE_Raw.rtf", ///
    replace ///
    b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
    label nogaps nodepvars nonotes ///
    title("Table 3: Baseline Fixed Effects Regression Results") ///
    mtitles("ln(Energy Intensity)") ///
    drop(yr_dummy*) ///                          // Hides the long list of year dummies
    scalars("industry_fe Industry-country FE" "year_fe Year FE") ///
    stats(N r2_w, labels("Observations" "Within R-squared") fmt(0 3)) ///
    addnotes("Standard errors clustered at the industry level." "Year dummies are included but not reported.")

* --- 4. Open the file ---
shell open "$output_dir/Table3_Baseline_FE_Raw.rtf"

**# Instrument Variable: S_EI
* ------------- 10. GENERATING INSTRUMENT FOR ENERGY SPILLOVER (IV_S_EI)
* Logic: Fixed 2007 Weights * Current Year Supplier Energy Shocks

* Load Base Year Weights (2007)
use "$input_dir/Master_Weights_2007.dta", clear

* Expand the 2007 static weights to cover the panel period (2008-2022)
expand 15
drop Year
bysort buyer_id supplier_id: gen Year = 2007 + _n

* Parse IDs for merging with yearly supplier shocks
gen Supplier_Country = substr(supplier_id, 1, 3)
gen Supplier_Sector  = substr(supplier_id, 5, .)

rename Supplier_Country Country
rename Supplier_Sector  Sector_Code

* Merge with the Yearly Supplier Energy Intensity Database
merge m:1 Year Country Sector_Code using "$working_dir/Database_EI_Supplier_Final.dta"
drop if _merge == 2

* Ensure the instrument does not include self-shocks
drop if supplier_id == buyer_id

* Handle missing EI data
replace EI_supplier = 0 if _merge == 1
drop _merge

* Calculate the IV Component
gen iv_ei_comp = 0
replace iv_ei_comp = weight * ln(EI_supplier) if EI_supplier > 0

* Aggregate to Buyer Level
gen Buyer_Country = substr(buyer_id, 1, 3)
gen Buyer_Sector  = substr(buyer_id, 5, .)

collapse (sum) IV_S_EI = iv_ei_comp, by(Year Buyer_Country Buyer_Sector)

* Formatting
rename Buyer_Country Country
rename Buyer_Sector  Sector_Code
save "$working_dir/Database_IV_EI.dta", replace

**# Instrument Variable: S_Tech
* ------------- 11. GENERATING INSTRUMENT FOR TECH SPILLOVER (IV_S_Tech)
use "$input_dir/Master_Weights_2007.dta", clear
expand 15
drop Year
bysort buyer_id supplier_id: gen Year = 2007 + _n

* Match IDs
split supplier_id, p("_") gen(s)
rename s1 Country
rename s2 Sector_Code

* Merge with the SAME Nominal Output Shocks
merge m:1 Year Country Sector_Code using "$working_dir/Tech_Capacity_Shocks.dta"
replace Tech_Output_Shock = 0 if _merge != 3
drop _merge

drop if supplier_id == buyer_id

* Formula: Weight_2007 * ln(Supplier_Output_t)
gen iv_tech_comp = weight * ln(Tech_Output_Shock) if Tech_Output_Shock > 0

* Aggregate for Buyer
split buyer_id, p("_") gen(b)
collapse (sum) IV_S_Tech = iv_tech_comp, by(Year b1 b2)

rename b1 Country
rename b2 Sector_Code
save "$working_dir/Database_IV_Tech.dta", replace

**# Bartik Model
* ------------- 12. 2SLS REGRESSION (BARTIK MODEL)
*** PART A: FINAL MASTER MERGE OF INSTRUMENTS ***
use "$working_dir/FINAL_DATA_REGRESSION.dta", clear

* Merge the Energy Instrument
merge 1:1 Year Country Sector_Code using "$working_dir/Database_IV_EI.dta", nogenerate

* Merge the Tech Instrument
merge 1:1 Year Country Sector_Code using "$working_dir/Database_IV_Tech.dta", nogenerate

* --- FINAL DATA CLEANUP & LOG TRANSFORMATIONS ---
* Create Year Dummies for the Regression
capture drop yr_dummy*
tabulate Year, gen(yr_dummy)

* Re-set Panel ID and industry_id just in case
capture drop industry_id
egen industry_id = group(Country Sector_Code)
xtset industry_id Year

* Final check for missing values in core variables
drop if lnEI == . | S_EI == . | S_Tech == .

save "$working_dir/FINAL_MASTER_FOR_ANALYSIS.dta", replace

*** PART B: CAUSAL ANALYSIS: 2SLS BARTIK REGRESSIONS ***

* --- MODEL 1: THE FULL DUAL IV MODEL (Instrumenting Both Energy & Tech) ---
xtivreg2 lnEI VA_per_Output ln_Energy_Price Service_Share Import_Share ///
    (S_EI S_Tech = IV_S_EI IV_S_Tech) yr_dummy2-yr_dummy15, fe cluster(industry_id)

* Capture diagnostics for the table
estadd scalar kp_lm = e(idp)
estadd scalar kp_f = e(rkf)
estadd local industry_fe "Yes"
estadd local year_fe "Yes"
estimates store model_dual_iv

*** PART C: EXPORTING TABLE ***
* Define labels for professional output
label variable lnEI "ln(Energy Intensity)"
label variable S_EI "S^EI (Energy Spillover)"
label variable S_Tech "S^T (Imported Tech Intake)"
label variable VA_per_Output "Value Added per Output"
label variable ln_Energy_Price "ln(PE/PQ)"
label variable Import_Share "Share of imported inputs"
label variable Service_Share "Share of service inputs"

* Export using esttab (Only the Dual IV model)
esttab model_dual_iv using "$output_dir/Bartik_Table.rtf", ///
    replace ///
    b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
    label nogaps nodepvars nonotes ///
    title("Table 3: Bartik 2SLS Regression Results") ///
    mtitles("Dual IV") ///
    drop(yr_dummy*) ///
    scalars("industry_fe Industry-country FE" "year_fe Year FE") ///
    stats(N r2_a kp_lm kp_f, ///
          labels("Observations" "Adj. R-squared" "KP LM test (p-val)" "KP Wald F test") ///
          fmt(0 3 3 2)) ///
    addnotes("Standard errors are clustered at the industry level." ///
             "KP LM test refers to the Kleibergen-Paap underidentification test." ///
             "KP Wald F test refers to the weak identification test.")

* Open the result file
shell open "$output_dir/Bartik_Table.rtf"

**# Diagnostic Tests
*** PART D: DIAGNOSTIC TESTS ***
xtivreg2 lnEI VA_per_Output ln_Energy_Price Service_Share Import_Share ///
    (S_EI S_Tech = IV_S_EI IV_S_Tech) yr_dummy2-yr_dummy15, ///
    fe cluster(industry_id) endog(S_EI S_Tech)

* Store the robust endogeneity stats
estadd scalar endog_stat = e(estat) 
estadd scalar endog_pval = e(estatp)
estadd scalar f_stat = .  
estadd scalar f_pval = .  
estimates store test_joint

* 3. First-Stage Instrument Strength Test for IV_S_EI
* Note: S_Tech is included here as an exogenous control based on the endogeneity test
xtreg S_EI IV_S_EI VA_per_Output ln_Energy_Price Service_Share Import_Share S_Tech yr_dummy2-yr_dummy15, fe cluster(industry_id)
* Run the F-test for the energy instrument
test IV_S_EI
* Store the F-test stats (test command saves to r() instead of e())
estadd scalar f_stat = r(F)
estadd scalar f_pval = r(p)
estadd scalar endog_stat = . 
estadd scalar endog_pval = . 
estimates store test_iv_ei

* 4. First-Stage Instrument Strength Test for IV_S_Tech
* Note: S_EI is included here as an exogenous control for the sake of this isolated test
xtreg S_Tech IV_S_Tech VA_per_Output ln_Energy_Price Service_Share Import_Share S_EI yr_dummy2-yr_dummy15, fe cluster(industry_id)
* Run the F-test for the tech instrument
test IV_S_Tech
* Store the F-test stats
estadd scalar f_stat = r(F)
estadd scalar f_pval = r(p)
estadd scalar endog_stat = . 
estadd scalar endog_pval = . 
estimates store test_iv_tech

* 5. Export the Combined Diagnostic Table
esttab test_joint test_iv_ei test_iv_tech using "$output_dir/Table_Supervisor_Diagnostics.rtf", ///
    replace ///
    title("Diagnostic Tests: Endogeneity and Instrument Strength") ///
    mtitles("DWH Test" "1st Stage: S_EI" "1st Stage: S_Tech") ///
    keep(S_EI S_Tech IV_S_EI IV_S_Tech) /// 
    scalars( ///
        "endog_stat Robust Endog. (Chi-sq)" ///
        "endog_pval Endog. p-value" ///
        "f_stat 1st Stage F-stat" ///
        "f_pval 1st Stage p-value" ///
    ) ///
    sfmt(3 4 2 4) /// 
    b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
    addnotes("Models 1 & 2: Difference-in-Sargan testing H0: Variable is exogenous." ///
             "Models 3 & 4: First-stage testing H0: Instrument is weak (Stock-Yogo threshold F > 10)." ///
             "Standard controls and year fixed effects are included in all models but suppressed for brevity.")

shell open "$output_dir/Table_Supervisor_Diagnostics.rtf"
