# The BI Guardrails Project
### *Using inferential statistics to make charts more useful*
Part 1 of ?: Percentage Bar Charts
----------------------------------

[Interact](https://tuohybuoy.shinyapps.io/uiuc_grade_explorer_with_inferential_guardrails) with the current application at rstudio.shinyapps.io.

## Intro

### Why This Project?

The strength of business intelligence, or BI, can also be its weakness. By themselves, charts and visuals are powerful tools for summarizing large datasets for a nontechnical audience. However, the same audience is often left to determine what conclusions to draw from the visual. Conclusions are often based on gut feelings. Arguably, this is the opposite of the desired goal when using data to aid decisionmaking.

For example, take the percentage bar chart. It's a useful tool for comparing proportions between groups of differing size. In an academic setting, it could compare the percentages of As that different instructors award to their students. Take an example where Prof. Richards has 100 students and Dr. Doom has 500:

![Richards vs. Doom A Grades Awarded](common/images/Richards_vs_Doom_Grades.png)

Here, it looks obvious that Prof. Richards is more likely to award As. 50% is certainly a higher proportion than 30%. But what if Richards only has ten students, or six? The chart doesn't help determine whether the difference is still meaningful, and in fact actively impedes efforts to determine this by looking exactly like the 100-vs.-500 case.

Workarounds exist, such as shading or setting bar thickness by the number of students for each instructor. However, they don't address the core issue that it's up to viewers to determine what differences are likely to be real.

### Inferential Statistics to the Rescue

Statistical techniques can readily provide ways to pinpoint differences that are more likely to be meaningful. Those same techniques can give insight into how big or small a difference is likely to be. Even better, they allow a viewer to choose precise cutoffs for the level of certainty they desire.

This Percentage Bar Chart tool uses four closely-related attributes to make this determination:
* *Sample size:* how many students does an instructor or group of instructors have?
* *Effect size:* how big or small is the difference between one instructor and others?
* *Significance:* how likely is the difference to be a false positive? The most typical cutoff for this likelihood is 5%.
* *Power:* if the "true" effect size is what the chart shows, how likely is it that we could correctly identify it? Typical cutoffs are 80%, 90% and 95%.

A rule of thumb: the smaller the difference between instructors, the more grades are required to identify the difference with a high degree of certainty.

Starting with the percentages and sample sizes, the application calculates apparent differences in the form of effect sizes. Finally, the application highlights only those differences that meet selected thresholds for statistical significance and power.

For more details about the statistical tests employed, see [The Statistics](#the-statistics) below.

A simple version of such a chart might look like this:

![Richards vs. Doom A Grades Awarded, with Effect Size](common/images/Richards_vs_Doom_Grades_with_Effect_Size.png)

Note: the Percentage Bar Chart tool can compare dozens or hundreds of instructors or courses. This makes it potentially useful even for subject matter experts, who might otherwise be hard-pressed to digest this volume of information.

![UIUC Grade Explorer with Inferential Guardrails - Start Page](common/images/App_Start_Page.png)

## The Pieces

## The Dataset

For a demonstration, the application uses the [University of Illinois GPA Dataset](https://github.com/wadefagen/datasets/tree/master/gpa) compiled by Prof. Wade Fagen-Ulmschneider, and used here with his kind permission.

The data summarizes grades awarded at the Champaign-Urbana campus of the University of Illinois from 2010 through 2018. Please see the end of this document for information and descriptive statistics.

## Usage

### Examples

What course subjects are significantly more (or less) likely to award As (or Fs) than the others?

![A Grade Percentages by Subject for Fall 2018](common/images/As_by_Subject.png)
*Accountancy seemed modestly less likely to award As and A+s than other subjects. in the Fall 2018 semester.*

If a subject awards significantly more As, is it more or less likely to award significantly more Fs?

![A Grade Percentages by Subject for Fall 2018](common/images/Fs_by_Subject.png)
*Accountancy was also marginally less likely to award Fs than other subjects.*

* Within a given subject, which course levels (100, 200, 300, etc.) differ significantly?
  * How do different subjects compare in terms of As awarded by level?
* Within a given subject and level, how do individual courses or instructors compare?
* For a given subject and level, has there been grade inflation over time?
* What happens when we raise or lower the certainty thresholds?

### Example Walkthrough

### Controls and Colors




## Details

### The [University of Illinois GPA Dataset](https://github.com/wadefagen/datasets/tree/master/gpa)

This dataset was provided to meet a number of FOIA requests. It summarizes grades earned in courses of more than 20 students where not all students earned the same grade. Smaller courses and uniformly-graded courses were excluded for privacy reasons.

The current dataset contains 2,583,054 grades awarded over nine years in 3,795 unique courses and 161 subjects. These courses were taught by 7,273 unique instructors (unique by name).

By year, grade totals range from 152,303 (2012) to 414,919 (2011).

For any given course in an academic term, grade counts range from 21 to 2,403.

Letter grades range from A+ to F, plus "W" for students who withdrew from a course after official drop deadline.

Note: "Year" in the dataset refers to calendar year, not academic year.

### App Controls

### The Statistics


### Handy Links

[The UIUC Course Catalog](https://courses.illinois.edu/)

## Left 