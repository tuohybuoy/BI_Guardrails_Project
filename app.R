#########################################################################
# The BI Guardrails Project
# Part 1 of ?: Inferential guardrails for percentage bar charts
#
# Shiny app to compare percentages of students earning particular grades
# by course, by instructor, etc.
# Use significance, power and effect size to give visual indicators of
# likely differences and their magnitudes.
#########################################################################

#----------------#
# Initialization #
#----------------#

# Required packages

library(tibble)
library(readr)
library(magrittr)
library(dplyr)
library(tidyr)
library(stringr)
library(broom)
library(ggvis)
library(scales)
# Libraries for power, effect size and parallelism
library(pwr)
library(iterators)
library(doParallel)
library(foreach)
library(shiny)

# Fire up parallelism

registerDoParallel()

# Project documentation & help link
projectLink <- "https://github.com/tuohybuoy/BI_Guardrails_Project/blob/master/README.md"

# Read course grade data.

CrsGrades <- read_csv("./common/data/UIUC_Course_Section_Grades.csv", col_types="iccccccccciiiiiiiiiiiiiiiidd") %>%
  # Append course title to subject and number
  mutate_at(vars(Course), list(~paste(., `Course Title`, sep=": ")))

# Grade dictionary
GradeQualPts <- read_delim("./common/data/UIUC_Course_Grade_Qual_Pts.txt", delim="\t")

# Define grouping fields
groupFields <- c("Year", "Course", "Subject", "Level", "Primary Instructor")
groupInitField <- "Course"

# Define filter fields and initial values for each
filterFields <- c("Year", "Term", "Subject", "Level")
allValChoice <- "(all)" # "All values" choice for each filter
filterInitVals <- c("2018", "Fall", "Chemistry", allValChoice)
names(filterInitVals) <- filterFields

# Test type choices: Binomial Exact, X2 Goodness of Fit, X2 Independence, or Auto
testTypes <- c("Auto", "Binomial Exact", "X2 Goodness of Fit", "X2 Independence")
testTypeInitVal = "Binomial Exact"
testType <- testTypeInitVal  # Placeholder for "Test Type" user input

# Magnitudes and cutoffs for effect sizes.
effectSizeMagnitudes <- data.frame(EffectSizeMagnitude=c("NA", "Tiny", "Small", "Medium", "Large"),
                                   # Conventional cutoffs for chi-square effect sizes
                                   EffectSizeX2=c(-0.00001,
                                                  0.00001,
                                                  cohen.ES(test="chisq", size="small")$effect.size,
                                                  cohen.ES(test="chisq", size="medium")$effect.size,
                                                  cohen.ES(test="chisq", size="large")$effect.size),
                                   # Cutoffs for exact tests of proportions
                                   EffectSizeExact=c(-0.00001,
                                                     0.00001,
                                                     cohen.ES(test="p", size="small")$effect.size,
                                                     cohen.ES(test="p", size="medium")$effect.size,
                                                     cohen.ES(test="p", size="large")$effect.size),
                                   stringsAsFactors=FALSE)

# Labels and colors for effect sizes, with sign included.
# The sign will indicate whether a given measure is smaller or larger in comparison to others.
effectSizeLblsColors <- data.frame(EffectSizeLabel=c("+ Large", "+ Medium", "+ Small", "+ Tiny", "NA", "- Tiny", "- Small", "- Medium", "- Large"),
                                   # Orange-blue diverging color palette, obtained from RColorBrewer site: http://colorbrewer2.org/
                                   EffectSizeColor=c("#2166ac", "#4393c3", "#92c5de", "#d1e5f0", "#f7f7f7", "#fee0b6", "#fdb863", "#e08214", "#b35806"),
                                   stringsAsFactors=FALSE)

effectSizeExcludeChoice <- "NA"      # Don't show "NA" as a dropdown choice for effect sizes
effectSizeDefaultChoice <- "Large"   # Default choice for Effect Size dropdown

# Controls to help determine whether to auto-resize chart as selections change
autoChartResize <- TRUE
pixelsPerBar <- 25
pixelsHeaderFooter <- 75
minChartHeight <- 300
chartHeightInitVal <- 725  # Height of chart in pixels

# Clone the input data for each filter field.
# This helps parallelize the setting of filter LOVs based on
# current grouping choice and filter defaults.

# inputDataList <- foreach(filterField=filterFields, .combine=rbind, .inorder=FALSE) %do% {
#   cbind(CrsGrades, filterField=filterField)
# } %>%
#   split(f=.$filterField)

# Helper functions

renameFilterFieldValCol <- function(filterField) { "filterValue" }

isNotNA <- function(x) { !is.na(x) }

# Given an effect-size label, get the correponding cutoff.

effectSizeCutoff <- function(testType, effectSizeLabel) {
  # Return cutoff corresponding to test type.
  case_when(
    str_detect(testType, "X2") ~ effectSizeMagnitudes$EffectSizeX2[effectSizeMagnitudes$EffectSizeMagnitude==effectSizeLabel],
    TRUE ~ effectSizeMagnitudes$EffectSizeExact[effectSizeMagnitudes$EffectSizeMagnitude==effectSizeLabel]
  )
}

# Function to label effect sizes for chi-square goodness of fit tests.
# Include sign to indicate direction of difference in a comparison:
# smaller = negative, larger = positive

labelEffectSizes <- function(testType, effectSizes) {
  
  effectSizeBreaks <- case_when(
    # For chi-square tests, use Cohen's convention for chi-square effect sizes
    str_detect(testType, "X2") ~ c(effectSizeMagnitudes$EffectSizeX2, Inf),
    # For exact tests, use Cohen's convention for proportion tests
    TRUE ~ c(effectSizeMagnitudes$EffectSizeExact, Inf)
  )

  # Label the absolute effect size
  effectLabels <- cut(abs(effectSizes),
                      breaks=effectSizeBreaks,
                      labels=effectSizeMagnitudes$EffectSizeMagnitude,
                      right=FALSE) %>%
    sapply(as.character) %>%
    # Convert missing values to string "NA"
    { ifelse(is.na(.), "NA", .) }
  
  # Prepend effect size by sign (direction) of effect.
  paste0(case_when(effectLabels == "NA" ~ "",
                   effectSizes > 0 ~ "+ ",
                   TRUE ~ "- "),
         effectLabels)
}


# Function to return column names containing grade counts.

getGradeColNames <- function(crsGradeDF, gradeVect) {
  return(intersect(colnames(crsGradeDF), gradeVect))
}

# Define grade list and default grades of interest
grades <- getGradeColNames(CrsGrades, GradeQualPts$Grade)
gradeInitVals <- grades[1:2]

# Function to populate LOVs with full lists of values available.
# Returrn list of filter fields and values.
# This logic is a quick fix until reactive LOVs are working.

populateLOVs <- function(inDF, filterFields, filterValues) {

    foreach(curField=filterFields, .combine=rbind, .inorder=FALSE) %do% {

      # Select values for the current field and uniquefy
      select_at(inDF, curField, renameFilterFieldValCol) %>%
      distinct() %>%
      # Add "(all)" choice to each filter
      bind_rows(data.frame(filterValue = allValChoice, stringsAsFactors=FALSE)) %>%
      mutate(filterField = curField,
             valueOrder = ifelse(filterValue==allValChoice, " ", filterValue)) %>%
      arrange(valueOrder) %>%
      select(-valueOrder)
  } %>%
    split(f=.$filterField)
  
}

# Function to dynamically repopulate LOVs for each filter field,
# depending on current grouping and filter defaults.
# This makes sure to populate LOVs with only relevant values,
# and to handle things when filter defaults return zero rows.

# Need to handle the case when one or fewer filters is set to specific value.

# populateLOVs <- function(inDF, filterFields, filterValues) {
#   
#   # Construct list. Each element corresponds to a single filter field, and the element values
#   # show the other filter fields and their current settings.
#   # Will use this to get the LOV for each filter field given the current settings of all
#   # other filters.
#   
#   otherFilterList <- foreach(curField=filterFields, .combine=bind_rows, .inorder=FALSE) %do% {
#     data.frame(otherField = filterFields,
#                # Filter settings, replacing "(all)" string with NA
#                otherValue = na_if(replace(filterInitVals, which(filterFields == curField), NA), allValChoice),
#                stringsAsFactors=FALSE) %>%
#       spread(otherField, otherValue) %>%
#       bind_cols(filterField=curField)
#   } %>%
#     split(f=.$filterField)
#   
#   # For each filter field, filter the input data given all other filter settings
#   # and construct the LOV from the results.
#   
#   foreach(curField=filterFields, .combine=rbind, .inorder=FALSE) %do% {
#     # Join input data to values of "other" filter fields
#     select(otherFilterList[[curField]], -filterField) %>%
#       select_if(isNotNA) %>%
#       inner_join(inDF) %>%
#       # Select any remaining values for the current field and uniquefy
#       select_at(curField, renameFilterFieldValCol) %>%
#       distinct() %>%
#       # Add "(all)" choice to each filter
#       bind_rows(data.frame(filterValue = allValChoice, stringsAsFactors=FALSE)) %>%
#       mutate(filterField = curField,
#              valueOrder = ifelse(filterValue==allValChoice, " ", filterValue)) %>%
#       arrange(valueOrder) %>%
#       select(-valueOrder)
#   } %>%
#     split(f=.$filterField)
#   
# }

# Function to adjust filter values depending on the current LOV list for each filter.
# If a filter setting is not in its current LOV, replace the setting with "(all)".

# adjustFilterValues <- function(filterLOVList, filterFields, filterValues) {
# 
#   filterNewVals <- foreach(curField=filterFields, .combine=c, .inorder=TRUE) %do% {
#     ifelse(filterValues[names(filterValues)==curField] %in% filterLOVList[[curField]]$filterValue,
#            filterValues[names(filterValues)==curField],
#            allValChoice)
#   }
#   names(filterNewVals) <- filterFields
#   filterNewVals
# }

# If needed, make the alpha threshold more strict according to the number
# of tests performed.

adjustAlpha <- function(alpha, alphaAdjust, nTests) {
  return(ifelse(alphaAdjust==TRUE, alpha/nTests, alpha))
}

# Helper function for resizing chart to fit the number of groups displayed

computeChartHeight <- function(autoChartResize, chartHeightInitVal,
                               numGroups, pixelsPerBar, pixelsHeaderFooter, minChartHeight) {
  ifelse(autoChartResize,
         max(minChartHeight, (numGroups*pixelsPerBar) + pixelsHeaderFooter),
         chartHeightInitVal)
}

#-----------------------------------------------------------#
# Functions to run statistical inference tests.             #
# Keep these functions separate to avoid slowing execution. #
#-----------------------------------------------------------#

# Function for exact binomial test.

BinomialExactTest <- function(gradeSummary, alpha, minPower) {
  
  # If more than one group to consider, run analysis.
  if (nrow(gradeSummary) > 1) { 
    
    # Run group-level analyses in parallel and combine results into data frame.
    gradeAnalysisDF <- foreach(gradeRow=iter(gradeSummary, by="row"), .combine=bind_rows, .inorder=TRUE,
                               .packages=c("pwr","tibble","dplyr")) %dopar%
                               {
                                 # Get grade counts and proportions for this group and outside groups as vectors.
                                 gradeCounts <- as.numeric(select(gradeRow, `Grades of Interest`, `Other Grades`, `Prop Grades of Interest`,
                                                                  `Outside Grades of Interest`, `Outside Other Grades`, `Prop Outside Grades of Interest`))
                                 thisCounts <- gradeCounts[1:2]
                                 propSpecGrades <- gradeCounts[3]
                                 outsideCounts <- gradeCounts[4:5]
                                 propOutsideSpecGrades <- gradeCounts[6]
                                 # Null hypothesis: proportion of specified grades in outside groups.
                                 H0Prop <- outsideCounts[1]/sum(outsideCounts)
                                 
                                 
                                 # Identify the smallest magnitude of effect size which the current test could
                                 # identify given the current group size and alpha + power settings.
                                 
                                 minEffectSizeMagnitude <- pwr.p.test(n=sum(thisCounts),
                                                             power=minPower,
                                                            sig.level=alpha,
                                                            alternative="two.sided"
                                                            )$h
                                 
                                 # Run test
                                 testResult <- binom.test(x=thisCounts, p=H0Prop, alternative="two.sided", conf.level=(1.0-alpha))
                                 
                                 # Get test results and sig level
                                 testStatistic <- testResult$statistic
                                 pValue <- as.numeric(testResult$p.value)
                                 confInt <- testResult$conf.int
                                 
                                 isSig <- (pValue <= alpha) # Significance threshold met?
                                 
                                 # If statistical significance achieved
                                 if (isSig) {
                                   
                                   # Effect size
                                   effectSize <- ES.h(p1=propSpecGrades, p2=propOutsideSpecGrades)
                                   
                                   # Only report effect size if it's at least equal to the smallest size
                                   # that the test could reasonably detect (given current confidence settings).
                                   
                                   if(abs(effectSize) < minEffectSizeMagnitude) {
                                     effectSize <- as.double(NA)
                                   }
                                   
                                 } else {  # Significance threshold not met
                                   effectSize <- as.double(NA)
                                 }
                                 
                                 # Add the computed statistics to the given row of data.
                                 add_column(gradeRow,
                                            `Test Statistic` = testStatistic,
                                            `p-Value` = pValue,
                                            `Diff CI Lower Bound` = confInt[1] - propOutsideSpecGrades,
                                            `Diff CI Upper Bound` = confInt[2] - propOutsideSpecGrades,
                                            `Statistical Significance Achieved` = isSig,
                                            `Effect Size` = effectSize,
                                            `Min Detectable Effect Size` = minEffectSizeMagnitude
                                 )
                               }
    
    # Insufficient number of groups to run analysis.
  } else {
    gradeAnalysisDF <- add_column(gradeSummary,
                                  `Test Statistic` = as.double(NA),
                                  `p-Value` = as.double(NA),
                                  `Diff CI Lower Bound` = as.double(NA),
                                  `Diff CI Upper Bound` = as.double(NA),
                                  `Statistical Significance Achieved` = FALSE,
                                  `Effect Size` = as.double(NA),
                                  `Min Detectable Effect Size` = as.double(NA)
    )
  }
  # Return data with test results added
  return(gradeAnalysisDF)
}

# Chi-square goodness-of-fit test.
# For each group, test grade proportions against all other groups combined.
# The combined other groups are considered the population against which
# to test the current group for fit.
# Works best when the combined size of other groups is much larger than
# the size of the group of interest.

# U R HERE. Check if it's possible to compute confidence intervals from Chi-Square test.

X2GoodnessofFitTest <- function(gradeSummary, alpha, minPower,
                                # Value to add to each cell in chi-square test.
                                # Useful for making test results less extreme when
                                # any observed or expected counts are zero.
                                adjustCellCountsBy = 0.0) {

  # If more than one group to consider, run analysis.
  if (nrow(gradeSummary) > 1) { 
    
    # Run group-level analyses in parallel and combine results into data frame.
    gradeAnalysisDF <- foreach(gradeRow=iter(gradeSummary, by="row"), .combine=bind_rows, .inorder=TRUE, .packages=c("pwr","tibble","dplyr")) %dopar%
    {
      # Get grade counts and proportions for this group and outside groups as vectors.
      gradeCounts <- as.numeric(select(gradeRow, `Grades of Interest`, `Other Grades`,
                                       `Outside Grades of Interest`, `Outside Other Grades`))
      thisCounts <- (gradeCounts[1:2] + adjustCellCountsBy)
      propSpecGrades <- thisCounts[1]/sum(thisCounts)
      outsideCounts <- (gradeCounts[3:4] + adjustCellCountsBy)
      propOutsideSpecGrades <- outsideCounts[1]/sum(outsideCounts)

      # Identify the smallest magnitude of effect size which the current test could
      # identify given the current group size and alpha + power settings.
      
      minEffectSizeMagnitude <- pwr.chisq.test(N=sum(thisCounts),
                                               df=length(thisCounts)-1,
                                               sig.level=alpha,
                                               power=minPower
      )$w
      
      # Run test
      testResult <- chisq.test(x=thisCounts, p=outsideCounts, rescale.p=TRUE, correct=FALSE)
      
      # Get test results and sig level
      testStatistic <- testResult$statistic
      pValue <- testResult$p.value
      
      isSig <- (pValue <= alpha) # Significance threshold met?
      
      # If statistical significance achieved
      if (isSig) {
        # Estimated effect size
        effectSize <- ES.w1(P0=outsideCounts/sum(outsideCounts), P1=thisCounts/sum(thisCounts))
        
        # Only report effect size if it's at least equal to the smallest size
        # that the test could reasonably detect (given current confidence settings).
        
        if(effectSize >= minEffectSizeMagnitude) {
          # Effect size detectable given settings. Add sign for direction of difference.
          effectSize <- ifelse(propSpecGrades < propOutsideSpecGrades, -effectSize, effectSize)
        } else {
          effectSize <- as.double(NA)
        }
        
        
      } else {  # Significance threshold not met
        isSig <- FALSE
        effectSize <- NA
      }
      
      # Add the computed statistics to the given row of data.
      add_column(gradeRow,
                 `Test Statistic` = testStatistic,
                 `p-Value` = pValue,
                 # Is the result statistically significant?
                 `Statistical Significance Achieved` = isSig,
                 `Effect Size` = effectSize,
                 `Min Detectable Effect Size` = minEffectSizeMagnitude
      )
      
    }
    # Insufficient number of groups to run analysis.
  } else {
    gradeAnalysisDF <- add_column(gradeSummary,
                                  `Test Statistic` = as.double(NA),
                                  `p-Value` = as.double(NA),
                                  `Statistical Significance Achieved` = FALSE,
                                  `Effect Size` = as.double(NA),
                                  `Min Detectable Effect Size` = as.double(NA)
    )
  }
  # Return data with test results added
  return(gradeAnalysisDF)
}

# Chi-square independence test.
# For each group, test independence of its grade distribution
# against all other groups combined, in a 2x2 contigency table.
# Works best when combined other groups are not much larger than
# the group of interest.

# U R HERE. Check if it's possible to compute confidence intervals from Chi-Square test.

X2IndependenceTest <- function(gradeSummary, alpha, minPower,
                               # Value to add to each cell in chi-square test.
                               # Useful for making test results less extreme when
                               # any observed or expected counts are zero.
                               adjustCellCountsBy = 0.0) {
  
  # If more than one group to consider, run analysis.
  if (nrow(gradeSummary) > 1) { 
    
    # Run group-level analyses in parallel and combine results into data frame.
    gradeAnalysisDF <- foreach(gradeRow=iter(gradeSummary, by="row"), .combine=bind_rows, .inorder=TRUE, .packages=c("pwr","tibble","dplyr")) %dopar%
    {
      # Get grade counts and proportions for this group and outside groups as vectors.
      gradeCounts <- as.numeric(select(gradeRow, `Grades of Interest`, `Other Grades`,
                                       `Outside Grades of Interest`, `Outside Other Grades`))
      thisCounts <- (gradeCounts[1:2] + adjustCellCountsBy)
      propSpecGrades <- thisCounts[1]/sum(thisCounts)
      outsideCounts <- (gradeCounts[3:4] + adjustCellCountsBy)
      propOutsideSpecGrades <- outsideCounts[1]/sum(outsideCounts)
      # 2x2 contingency table of grades and groups
      gradeCountCT <- matrix(c(thisCounts, outsideCounts), nrow=2, byrow=TRUE)
      
      # Identify the smallest magnitude of effect size which the current test could
      # identify given the current group size and alpha + power settings.
      
      minEffectSizeMagnitude <- pwr.chisq.test(N=sum(gradeCountCT),
                                               df=((nrow(gradeCountCT)-1) * (ncol(gradeCountCT)-1)),
                                               sig.level=alpha,
                                               power=minPower
      )$w

      # Run test
      testResult <- chisq.test(gradeCountCT)
      
      # Get test results and sig level
      testStatistic <- testResult$statistic
      pValue <- testResult$p.value
      
      isSig <- (pValue <= alpha) # Significance threshold met?
      
      # If statistical significance achieved
      if (isSig) {
        # Effect size
        effectSize <- ES.w2(gradeCountCT/sum(gradeCountCT))
        
        # Only report effect size if it's at least equal to the smallest size
        # that the test could reasonably detect (given current confidence settings).
        
        if(effectSize >= minEffectSizeMagnitude) {
          # Effect size detectable given settings. Add sign for direction of difference.
          effectSize <- ifelse(propSpecGrades < propOutsideSpecGrades, -effectSize, effectSize)
        } else {
          effectSize <- as.double(NA)
        }
        
      } else {  # Significance threshold not met
        isSig <- FALSE
        effectSize <- NA
      }
      
      # Add the computed statistics to the given row of data.
      add_column(gradeRow,
                 `Test Statistic` = testStatistic,
                 `p-Value` = pValue,
                 # Is the result statistically significant?
                 `Statistical Significance Achieved` = isSig,
                 `Effect Size` = effectSize,
                 `Min Detectable Effect Size` = minEffectSizeMagnitude
      )
      
    }
    # Insufficient number of groups to run analysis.
  } else {
    gradeAnalysisDF <- add_column(gradeSummary,
                                  `Test Statistic` = as.double(NA),
                                  `p-Value` = as.double(NA),
                                  `Statistical Significance Achieved` = FALSE,
                                  `Effect Size` = as.double(NA),
                                  `Min Detectable Effect Size` = as.double(NA)
    )
  }
  # Return data with test results added
  return(gradeAnalysisDF)
}

# Generate list of LOVs for filter fields.

filterLOVList <- populateLOVs(CrsGrades, filterFields, filterInitVals)

#-----------#
# Shiny App #
#-----------#


# Page layout and controls

ui <- fixedPage(
  # CSS to help titles and labels look reasonable.
  # Disable code to scale(), which could otherwise help with laptop displays that are scaled up.
  # In Firefox and Opera, scale() causes flickering tooltips.
  # Chrome and Edge flickering can be remedied with CSS: .tooltip, .popover { pointer-events: none; }
  # Not sure about Safari.
  # scale() code from: https://www.developerdrive.com/scaling-web-page-elements-using-the-css3-scale-transform/
  tags$head(
    tags$style(HTML(
      # "body { 
      #    -moz-transform: translate(-10%, -10%) scale(0.8, 0.8);
      #    -ms-transform: translate(-10%, -10%) scale(0.8, 0.8);
      #    -webkit-transform: translate(-10%, -10%) scale(0.8, 0.8);
      #    -o-transform: translate(-10%, -10%) scale(0.8, 0.8);
      #    transform: translate(-10%, -10%) scale(0.8, 0.8);
      # }
      "h2 {
         font-size: x-large; margin-left: 10px;
      } .col-sm-2 {
        padding-top: 5px;
      } .project-link {
        width: 115px;
        text-align: center;
        vertical-align: middle;
        background-color: #f5f5f5;
        border-style: solid;
        border-width: 1px;
        border-color: #cccccc;
        padding: 5px;
        -moz-border-radius: 5px;
        border-radius: 5px;
      } .help-block {
         margin-left: 10px;
      } .shiny-input-panel {
         padding: 6px;
      } strong {
         margin-bottom: 10px;
      } label {
         font-weight: 500;
         font-style: italic;
      } .form-group, .selectize-control, .checkbox {
         margin-bottom: 4px;
      }.box-body {
         padding-bottom: 4px;
      }"
    ))
  ),
  fixedRow(column(width=10, titlePanel("Where Are Particular UIUC Course Grades Significantly Rare or Common?")),
           column(width=2, div(class="project-link", a(href=projectLink, target="_blank", "Project & Documentation")))
  ),
  helpText("Explore which UIUC courses, instructors, etc. award significantly different grades than others. Colors indicate size and direction of difference."),
  sidebarLayout(
    sidebarPanel(
      # Choose from available course grades
      inputPanel(
        verticalLayout(
          strong("Select Grades of Interest"),
                 selectInput(inputId="Grades", label=NULL,
                             choices=grades, selected=gradeInitVals,
                             multiple=TRUE)
        )
      ),
      # Choose grouping for grades
      inputPanel(
        verticalLayout(
          strong("Group Grades By"),
                 selectInput(inputId="Grouping", label=NULL,
                  choices=groupFields, selected=groupInitField)
        )
      ),
      # Dropdowns of filters
      inputPanel(
        verticalLayout(
          strong("Filter By"),
                 selectInput(inputId=filterFields[1], label=filterFields[1],
                             choices=filterLOVList[[filterFields[1]]]$filterValue,
                             selected=filterInitVals[1]),
                 selectInput(inputId=filterFields[2], label=filterFields[2],
                             choices=filterLOVList[[filterFields[2]]]$filterValue,
                             selected=filterInitVals[2]),
                 selectInput(inputId=filterFields[3], label=filterFields[3],
                             choices=filterLOVList[[filterFields[3]]]$filterValue,
                             selected=filterInitVals[3]),
                 selectInput(inputId=filterFields[4], label=filterFields[4],
                             choices=filterLOVList[[filterFields[4]]]$filterValue,
                             selected=filterInitVals[4])
        )
      ),
      inputPanel(
        verticalLayout(
          strong("Choose Confidence Settings"),
          # Minimum desired power
          sliderInput(inputId="MinPower", label="Min Chance of Detecting Diff",
                      min=50, max=100, value=90, step=1, post="%"),
          # Alpha threshold
          sliderInput(inputId="Alpha", label="Max Chance of False Positive",
                      min=0.1, max=20, value=5, step=0.1, post="%"),
          checkboxInput(inputId="AlphaAdjust", label="Adjust False Positive Test by Number of Groups", value=TRUE)
        )
      ),
      width=3
    ),
    mainPanel(
      tabsetPanel(
        tabPanel("Grades",
                 div(style='height:750px; width:750; overflow-y: scroll',
                     ggvisOutput(plot_id="outGradePlot"))
        ),
        tabPanel("Table", tableOutput(outputId="outTable"))
      )
    )
  )
)

# Page business logic and output

server <- function (input, output){
  
  # Reactive: how to group results (by course, instructor, etc.)
  groupVal <- reactive({ input$Grouping })
  
  # Reactive: specified filter values, if any
  filterVals <- reactive({
    fv <- sapply(filterFields, function(ff) { input[[ff]] })
    names(fv) <- filterFields
    filterVals <- fv[fv != allValChoice]
    filterVals
  })
  
  # Reactive: confidence level (given value of Alpha)
  confLevel <- reactive({
    paste0((100 - input$Alpha), "%", collapse="")
  })
  
  # Reactives: titles and subtitles for charts and x-axes
  gradePlotXAxisTitle <- reactive({
    paste("Percentage of", paste0(input$Grades, collapse="/"), "Grades", sep=" ", collapse="")
  })
  mainGradePlotTitle <- reactive({
    paste(gradePlotXAxisTitle(), "by", input$Grouping, sep=" ", collapse="")
  })
  CIPlotXAxisTitle <- reactive({
    paste("Difference in", paste0(input$Grades, collapse="/"), "Grades from Others", sep=" ", collapse="")
  })
  mainCIPlotTitle <- reactive({
    paste0(str_sub(CIPlotXAxisTitle(), 1, -2), " ", input$Grouping, "s", sep=" ", collapse="")
  })
  subTitle <- reactive({
    paste(paste0(names(filterVals()),":"), filterVals(), sep=" ", collapse="; ")
  })
  
  # Reactive function to return grouped grade counts
  # and statistics for output.
  
  gradeAnalysisDF <- reactive({ 
    
    # Get grouping and filter values
    
    groupVal <- input$Grouping
    filterVals <- sapply(filterFields, function(ff) { input[[ff]] })
    names(filterVals) <- filterFields
    # Get grades of interest
    gradeVals <- input$Grades
    # Get specified Alpha, Alpha adjustment, min desired effect size, and min a-priori power.
    alpha <- input$Alpha/100
    alphaAdjust <- input$AlphaAdjust
    minPower <- input$MinPower/100
    
    # Group and filter the data as specified.
    
    # If no filtering of data needed
    if (all(filterVals == allValChoice)) {
      
      gradeDF <- select_at(CrsGrades, c(groupVal, gradeVals, "Total Grades"))
      
      # Filter data by input selections if needed.
    } else {
      specFilterVals <- filterVals[filterVals != allValChoice]
      # Start with data frame of filter specifications.
      gradeDF <- data.frame(filterField=names(specFilterVals),
                            filterVal=specFilterVals,
                            stringsAsFactors=FALSE) %>%
        spread(key=filterField, value=filterVal) %>%
        # Join filter specs to data.
        inner_join(CrsGrades, by=names(specFilterVals)) %>%
        select_at(c(groupVal, gradeVals, "Total Grades"))
    }
    
    # For each group, get counts of the grades specified in the "Grades" dropdown,
    # plus counts of all other grades. Will use this to build contingency table.
    
    # If at least one grade type is selected:
    if (length(gradeVals) > 0) {
      groupGradeCount <- select_at(gradeDF, c(groupVal, gradeVals)) %>%
        gather(key="Grade", value="Grade Count", !!gradeVals) %>%
        # Group by the field specified in the "Grouping" dropdown
        group_by_at(groupVal) %>%
        summarize(`Grades of Interest` = sum(`Grade Count`))
    } else {  # No grade type selected
      groupGradeCount <- select_at(gradeDF, groupVal) %>%
        # No grade type selected, so grade count is zero
        add_column(`Grade Count` = 0) %>%
        # Group by the field specified in the "Grouping" dropdown
        group_by_at(groupVal) %>%
        summarize(`Grades of Interest` = sum(`Grade Count`))
    }
    
    groupGradeSummary <- inner_join(groupGradeCount,
                                    select_at(gradeDF, c(groupVal, "Total Grades")) %>%
                                      rename(`Grade Count` = `Total Grades`) %>%
                                      group_by_at(groupVal) %>%
                                      summarize(`Total Grades` = sum(`Grade Count`)),
                                    by=groupVal) %>%
      # Compute the number of grades not in the user's selection
      mutate(`Other Grades` = `Total Grades` - `Grades of Interest`)
    
    # Grade counts across all groups.
    # Will use this to simplify construction of the contingency table.
    overallGradeSummary <- summarize(groupGradeSummary,
                                     `Total Grades of Interest` = sum(`Grades of Interest`),
                                     `Total Other Grades` = sum(`Other Grades`))
    
    # Generate summary table with rows that show the grade count for each group,
    # plus the grade counts for all other groups (outside the group described by the row).
    
    gradeSummary <- add_column(groupGradeSummary, !!! overallGradeSummary) %>%
      mutate(`Prop Grades of Interest` = `Grades of Interest` / `Total Grades`,
             `Outside Grades of Interest` = `Total Grades of Interest` - `Grades of Interest`,
             `Outside Other Grades` = `Total Other Grades` - `Other Grades`,
             `Prop Outside Grades of Interest` = `Outside Grades of Interest` / (`Outside Grades of Interest` + `Outside Other Grades`))
    
    # If necessary, adjust alpha by the number of tests
    alpha <- adjustAlpha(alpha, alphaAdjust, nrow(gradeSummary))
    
    # If no grade type specified, don't run inferential tests.
    if (length(gradeVals) == 0) {
      gradeAnalysisDF <- add_column(gradeSummary,
                                    `Test Statistic` = as.double(NA),
                                    `p-Value` = as.double(NA),
                                    `Statistical Significance Achieved` = FALSE,
                                    `Effect Size` = as.double(NA),
                                    `Min Detectable Effect Size` = as.double(NA))
      # Otherwise run appropriate inferential test on each row of data, and return data + results.
    } else if (testType=="Binomial Exact") {
      gradeAnalysisDF <- BinomialExactTest(gradeSummary, alpha, minPower)
    } else if (testType=="X2 Goodness of Fit") {
      gradeAnalysisDF <- X2GoodnessofFitTest(gradeSummary, alpha, minPower)
    } else if (testType=="X2 Independence") {
      gradeAnalysisDF <- X2IndependenceTest(gradeSummary, alpha, minPower)
    }

    # Label effect sizes and assign colors for plotting.
    gradeAnalysisDF %<>%
      mutate(EffectSizeLabel = labelEffectSizes(testType, `Effect Size`)) %>%
      inner_join(effectSizeLblsColors, by="EffectSizeLabel") %>%
      rename(`Effect Size Magnitude` = EffectSizeLabel)
    
    # Return computations from the reactive block
    
    select_at(gradeAnalysisDF, c(groupVal,
                                 "Grades of Interest",
                                 "Other Grades",
                                 "Prop Grades of Interest",
                                 "Outside Grades of Interest",
                                 "Outside Other Grades",
                                 "Prop Outside Grades of Interest",
                                 "Test Statistic",
                                 "p-Value",
                                 "Diff CI Lower Bound",
                                 "Diff CI Upper Bound",
                                 "Statistical Significance Achieved",
                                 "Effect Size",
                                 "Effect Size Magnitude",
                                 "EffectSizeColor",
                                 "Min Detectable Effect Size"))
    
    
  })
  
  # Count bars in the plot, to help compute chart height
  numGroups <- reactive({
    return(nrow(gradeAnalysisDF()))
  })
  
  # Calculate the greatest number of characters in a y-axis label.
  # Helps compute plot width.
  yLabelWidth <- reactive({
    return(max(nchar(gradeAnalysisDF()[1])))
  })
  
  # Generate GGVis grade plot.
  gradePlot <- reactive({
    
    # Generate symbols for chart items for use in GGVis' formula-type interface.
    xVar <- prop("x2", as.symbol("Prop Grades of Interest"))
    yVar <- prop("y", as.symbol(groupVal()))
    fillVar <- prop("fill", as.symbol("Effect Size Magnitude"))
    
    # Create offset to make sure y-axis intersects with x-axis at x==0.
    yOffset <- scaled_value("x", 0)
    
    # Generate plot and tooltip function
    gradeAnalysisDF() %>%
      ggvis() %>%
      layer_rects(x=0, x2=xVar, y=yVar, height=band(), fill=fillVar) %>%
      add_axis("y", offset=yOffset, title="", grid=FALSE, tick_size_major=0, tick_padding=5,
               properties = axis_props(
                 labels = list(fontSize=12)
               )) %>%
      add_axis("x", format=".0%", title=gradePlotXAxisTitle(), grid=FALSE) %>%
      # A hack to show a plot title
      add_axis("x", orient = "top", ticks = 0, title=mainGradePlotTitle(),
               properties = axis_props(
                 axis = list(stroke="white"),
                 labels = list(fontSize=0),
                 title = list(fontSize=14))) %>%
      add_legend("fill", title="Difference From Others",
                 values=effectSizeLblsColors$EffectSizeLabel,
                 properties = legend_props(
                   title = list(fontSize=12),
                   labels = list(fontSize=12)
                 )) %>%
      scale_ordinal("fill", domain=effectSizeLblsColors$EffectSizeLabel,
                    range=effectSizeLblsColors$EffectSizeColor) %>%
      # Function for interactive tooltips
      add_tooltip(
        function(g) {
          if (is.null(g)) return(NULL)
          # To handle intermittent error when data frame does not contain grouping column
          if (! groupVal() %in% colnames(g)) return(NULL)
          if (is.null(g[, groupVal()])) return(NULL)
          curGroupVal <- as.character(g[1, groupVal()])
          curRec <- filter_at(gradeAnalysisDF(), groupVal(), all_vars(. == curGroupVal))
          paste(
            paste0(groupVal(), ": ", "<b>", curGroupVal, "</b>", collapse=""),
            paste0("Number of ", paste0(input$Grades, collapse="/"), " Grades: ",
                   "<b>", as.character(curRec$`Grades of Interest`), "</b>",
                   sep=" ", collapse=""),
            paste0("Percentage of ", paste0(input$Grades, collapse="/"), " Grades: ",
                   "<b>", percent(curRec$`Prop Grades of Interest`), "</b>",
                   sep=" ", collapse=""),
            paste0("Difference from Other ", groupVal(), "s: ",
                   "<b>", curRec$`Effect Size Magnitude`, "</b>",
                   sep=" ", collapse=""),
            paste0("Difference Range: ", 
                   "<b>", as.character(abs(round(ifelse(curRec$`Diff CI Lower Bound` < 0 & curRec$`Diff CI Upper Bound` <= 0,
                                                        curRec$`Diff CI Upper Bound`,
                                                        curRec$`Diff CI Lower Bound`)  * 100, digits=1))), "% ",
                   ifelse(curRec$`Diff CI Lower Bound` < 0 & curRec$`Diff CI Upper Bound` > 0, "Lower", ""),
                   " to ",
                   as.character(abs(round(ifelse(curRec$`Diff CI Lower Bound` < 0 & curRec$`Diff CI Upper Bound` <= 0,
                                                 curRec$`Diff CI Lower Bound`,
                                                 curRec$`Diff CI Upper Bound`) * 100, digits=1))), "% ", 
                   ifelse(curRec$`Diff CI Upper Bound` <= 0, "Lower", "Higher"),
                   "</b>",
                   sep=" ", collapse=""),
            sep="<br />"
          )
        }, on="hover") %>%
      set_options(height=computeChartHeight(autoChartResize, chartHeightInitVal,
                                            numGroups(), pixelsPerBar, pixelsHeaderFooter,
                                            minChartHeight),
                  width="auto")
  })
  
  # Render plot
  gradePlot %>% bind_shiny("outGradePlot")

  # Render table.
  output$outTable <- renderTable({
    select(gradeAnalysisDF(), -EffectSizeColor)
  })
  
}

# Activate page

shinyApp(ui = ui , server = server)


