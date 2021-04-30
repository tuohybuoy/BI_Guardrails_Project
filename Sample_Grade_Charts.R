# Example charts for ReadMe to the BI Guardrails Project.

library(tibble)
library(stringr)
library(dplyr)
library(tidyr)
library(magrittr)
library(ggplot2)
library(scales)
library(pwr)
library(iterators)
library(foreach)

# Basic percentage bar chart

sampleProfGrades <- tibble(profName = c("Reed Richards", "Doctor Doom", "Clark Kent"),
                           profStudents = c(100, 500, 10),
                           propAGrades = c(0.5, 0.3, 0.8))

ggplot(sampleProfGrades, aes(x=profName, y=propAGrades, fill=profName)) +
  geom_bar(stat="identity", fill="#d7d7d7") +
  scale_x_discrete(limits=levels(as.factor(sampleProfGrades$profName))) +
scale_y_continuous(labels = scales::percent, expand=c(0, 0), limits=c(0,1)) +
  coord_flip() +
  theme_bw() +
  theme(legend.position="none") +
  labs(title="% As Awarded by Instructor",
       x="", y="% A Grades")

# Compute significance of the difference of each instructor's As from the other

sampleProfGrades %<>% mutate(numAGrades = as.integer(profStudents * propAGrades),
                                numOtherGrades = profStudents - numAGrades)

sampleProfGrades$outsideAGrades <- sapply(seq(1, nrow(sampleProfGrades)),
                                          function(i) { sum(sampleProfGrades$numAGrades[-i]) } )
sampleProfGrades$outsideOtherGrades <- sapply(seq(1, nrow(sampleProfGrades)),
                                          function(i) { sum(sampleProfGrades$numOtherGrades[-i]) } )

# Cutoffs for test significance and achieved power
alpha = 0.05
adjustedAlpha <- alpha / nrow(sampleProfGrades)
minPower <- 0.8

# Run exact binomial tests to compare each instructor to the other.
sampleProfGrades <- foreach(gradeRow=iter(sampleProfGrades, by="row"),
                            .combine=rbind, .inorder=TRUE) %do% {

  thisGrades <- c(as.integer(select(gradeRow, numAGrades, numOtherGrades)))
  outsideGrades <- c(as.integer(select(gradeRow, outsideAGrades, outsideOtherGrades)))

  # Initialize effect size and achieved power to zero (NS)
  gradeTestEffectSize <- 0.0
  gradeTestAchievedPower <- 0.0
  
  # Run test
  gradeTest <- binom.test(x = thisGrades,
                          p = outsideGrades[1]/sum(outsideGrades),
                          alternative = "two.sided",
                          conf.level= 1 - adjustedAlpha)
  
  # If significance threshold met, compute effect size and achieved power
  if (gradeTest$p.value <= adjustedAlpha) {
    gradeTestEffectSize <- ES.h(p1 = thisGrades[1]/sum(thisGrades),
                                p2 = outsideGrades[1]/sum(outsideGrades))

    gradeTestAchievedPower <- pwr.p.test(h=gradeTestEffectSize,
                                         n=sum(thisGrades),
                                         sig.level=adjustedAlpha,
                                         alternative="two.sided"
                                         )$power
    
    # If minimum achieved power not reached, show zero for effect size
    if (gradeTestAchievedPower < minPower) {
      gradeTestEffectSize <- 0.0
    }
    
  }

  # Add test results to data row
  add_column(gradeRow, testStatistic = gradeTest$statistic,
             pValue = gradeTest$p.value,
             effectSize = gradeTestEffectSize,
             achievedPower = gradeTestAchievedPower)
  
}

# Chart grade comparison with discrete effect size shown.

# Define colors and labels for effect size.
EffectSizeColor = c("#b35806", "#e08214", "#fdb863", "#fee0b6", "#e7e7e7", "#d1e5f0", "#92c5de", "#4393c3", "#2166ac")
EffectSizeLabel = c("- Large", "- Medium", "- Small", "- Tiny", "NA", "+ Tiny", "+ Small", "+ Medium", "+ Large")
names(EffectSizeColor) <- EffectSizeLabel

# Function to label effect sizes for chi-square goodness of fit tests.
# Include sign to indicate direction of difference in a comparison:
# smaller = negative, larger = positive

labelEffectSizes <- function(testType, effectSizes) {
  
  effectSizeBreaks <- case_when(
    # For chi-square tests, use Cohen's convention for chi-square effect sizes
    str_detect(testType, "X2") ~ c(-0.00001, 0.00001,
                                   cohen.ES(test="chisq", size="small")$effect.size,
                                   cohen.ES(test="chisq", size="medium")$effect.size,
                                   cohen.ES(test="chisq", size="large")$effect.size,
                                   Inf),
    # For exact tests, use Cohen's convention for proportion tests
    TRUE ~ c(-0.00001, 0.00001,
             cohen.ES(test="p", size="small")$effect.size,
             cohen.ES(test="p", size="medium")$effect.size,
             cohen.ES(test="p", size="large")$effect.size,
             Inf)
  )
  
  # Label the absolute effect size
  effectLabels <- cut(abs(effectSizes),
                      breaks=effectSizeBreaks,
                      labels=c("NA", "Tiny", "Small", "Medium", "Large"),
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

# Match effect sizes to colors and labels
sampleProfGrades %<>% mutate(effectSizeLabel = labelEffectSizes("Exact", effectSize))

# Chart

ggplot(sampleProfGrades, aes(x=profName, y=propAGrades,
                             fill=factor(effectSizeLabel, levels=EffectSizeLabel, ordered=TRUE))) +
  geom_bar(stat="identity") +
  scale_x_discrete(limits=levels(as.factor(sampleProfGrades$profName))) +
  scale_fill_manual(values = EffectSizeColor,
                    labels = EffectSizeLabel,
                    limits = EffectSizeLabel,
                    drop = FALSE) +
  scale_y_continuous(labels = scales::percent, expand=c(0, 0), limits=c(0,1)) +
  coord_flip() +
  theme_bw() +
  guides(fill = guide_legend(nrow=1, override.aes = list(size=5))) +
  theme(legend.position="bottom") +
  labs(title="% As Awarded by Instructor",
    x="", y="% A Grades", fill="Difference")


