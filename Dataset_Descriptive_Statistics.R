# Descriptive statistics for the UIUC GPA Dataset.

library(readr)
library(magrittr)
library(dplyr)
library(tidyr)

# Read course grade data.

CrsGrades <- read_csv("./common/data/UIUC_Course_Section_Grades.csv", col_types="iccccccccciiiiiiiiiiiiiiiidd") %>%
  # Append course title to subject and number
  mutate_at(vars(Course), list(~paste(., `Course Title`, sep=": ")))

# Total grades
summarize(CrsGrades, `Grade Total`=sum(`Total Grades`))

# Distinct courses
distinct(CrsGrades, Course) %>%
  summarize(`Unique Courses`=n())

# Distinct subjects
distinct(CrsGrades, Subject) %>%
  summarize(`Unique Subjects`=n())

# Distinct instructor names
distinct(CrsGrades, `Primary Instructor`) %>%
  summarize(`Unique Instructor Names`=n())

# Grade counts by year
group_by(CrsGrades, Year) %>%
  summarize(`Grade Total`=sum(`Total Grades`)) %>%
  arrange(`Grade Total`)

# Grade counts by year and term
group_by(CrsGrades, Term, Year) %>%
  summarize(`Grade Total`=sum(`Total Grades`)) %>%
  print(n=Inf)

# Min and max grades for any given course
group_by(CrsGrades, Semester, Course) %>%
  summarize(`Course Grades`=sum(`Total Grades`)) %>%
  summarize(`Min Grades`=min(`Course Grades`), `Max Grades`=max(`Course Grades`)) %>%
  arrange(`Max Grades`) %>%
  print(n=Inf)
