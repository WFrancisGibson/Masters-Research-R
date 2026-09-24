### NOTES #####################################################################

# For each R output, creates files of versions
# V1  = (cal_time, dev_time, cumpaid,ocl)
# V2  = (cal_time, dev_time, cumpaid, ocl, txn_type, multiplier)
# V3 (V2 into RNN layers + rest of derived features into FC layer)



# Relative to the working directory (wrap in here::here() if you prefer)

# filepaths noInf
fp_in     <- 'Datasets/R Outputs/test_incurred_dataset_noInf.csv'
fp_out_v1 <- 'Datasets/Python Inputs/V1/noInf/'
fp_out_v2 <- 'Datasets/Python Inputs/V2/noInf/'
fp_out_v3 <- 'Datasets/Python Inputs/V3/noInf/'

# filepaths Inflated
# fp_in     <- 'Datasets/R Outputs/test_incurred_dataset_Inflated.csv'
# fp_out_v1 <- 'Datasets/Python Inputs/V1/Inflated/'
# fp_out_v2 <- 'Datasets/Python Inputs/V2/Inflated/'
# fp_out_v3 <- 'Datasets/Python Inputs/V3/Inflated/'


### FUNCTIONS #################################################################

payment_types <- c('P', 'PMi', 'PMa')

# Helpers that return NA where pandas would return NaN (e.g. nothing to take
# the max of). The NAs become -1 later, as with fillna(-1) in Python.
last_value <- function(x) {
    if (length(x) == 0) {
        NA_real_ } else {
        x[length(x)]
    }
}
safe_mean  <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) == 0) {
    NA_real_
  } else {
    mean(x)
  }
}
safe_var   <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) < 2) {
    NA_real_
  } else {
    var(x)
  }
}
safe_max   <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) == 0) {
    NA_real_
  } else {
    max(x)
  }
}

# In the functions below:
#   cl  = all transactions of one claim, in their original row order
#   pay = the payment transactions of that claim (P, PMi, PMa)
#   rev = the revision transactions of that claim (everything except P)
#   c   = the censoring (prediction) time

get_ultimate <- function(cl) {
  # Ultimate claim cost for the claim
  safe_max(cl$cumpaid)
}

get_incurred <- function(cl, c) {
  # Estimated incurred claim cost at the last transaction strictly before c
  last_value(cl$incurred[which(cl$txn_time < c)])
}

get_num_payments  <- function(pay, c){
    length(which(pay$txn_time <= c))
}
get_mean_payments <- function(pay, c) {
  safe_mean(pay$payments[which(pay$txn_time <= c)])
}
get_var_payments  <- function(pay, c) {
  safe_var(pay$payments[which(pay$txn_time <= c)])
}
get_max_payments  <- function(pay, c) {
  safe_max(pay$payments[which(pay$txn_time <= c)])
}
get_cumpaid       <- function(pay, c) {
  safe_max(pay$cumpaid[which(pay$txn_time <= c)])
}

get_case_estimate <- function(cl, c) {
  temp <- cl[which(cl$txn_time <= c), ]
  if (nrow(temp) == 0) return(NA_real_)
  temp$incurred[which(temp$txn_time == max(temp$txn_time))[1]]
}

get_num_revisions <- function(rev, c) {
  length(which(rev$txn_time <= c))
}

get_upward_revisions <- function(rev, c) {
  revisions <- diff(rev$incurred[which(rev$txn_time <= c)])
  sum(revisions > 0, na.rm = TRUE)
}

get_total_variation <- function(rev, c) {
  temp <- rev[which(rev$txn_time <= c), ]
  if (nrow(temp) == 0) return(NA_real_)
  init_est <- temp$incurred[which(temp$txn_time == min(temp$txn_time))[1]]
  cur_est  <- temp$incurred[which(temp$txn_time == max(temp$txn_time))[1]]
  cur_est - init_est
}

make_index_rows <- function(cl) {
  # All index rows for one claim: one per censoring time c, running from the
  # (rounded up) first transaction time to one before the (rounded up) last
  start <- ceiling(min(cl$txn_time))
  end   <- ceiling(max(cl$txn_time))
  if (end <= start) return(NULL)          # Python's range(start, end) is empty

  cs  <- seq(start, end - 1)
  pay <- cl[cl$txn_type %in% payment_types, ]
  rev <- cl[!(cl$txn_type %in% 'P'), ]

  cbind(
    claim_no        = cl$claim_no[1],
    c               = cs,
    dev_quarter     = cs - start + 1,
    occ_quarter     = start,
    claim_size      = get_ultimate(cl),
    incurred        = sapply(cs, get_incurred,         cl  = cl),
    case_estimate   = sapply(cs, get_case_estimate,    cl  = cl),
    num_payments    = sapply(cs, get_num_payments,     pay = pay),
    mean_payments   = sapply(cs, get_mean_payments,    pay = pay),
    var_payments    = sapply(cs, get_var_payments,     pay = pay),
    max_payment     = sapply(cs, get_max_payments,     pay = pay),
    cumpaid         = sapply(cs, get_cumpaid,          pay = pay),
    num_revisions   = sapply(cs, get_num_revisions,    rev = rev),
    num_upward      = sapply(cs, get_upward_revisions, rev = rev),
    total_variation = sapply(cs, get_total_variation,  rev = rev)
  )
}

rename_cols <- function(df, old, new) {
  names(df)[match(old, names(df))] <- new
  df
}

fill_na <- function(df, value = -1) {
  df[] <- lapply(df, function(col) { col[is.na(col)] <- value; col })
  df
}

### DATA MANIPULATION #########################################################

# Reading data
data <- read.csv(fp_in, stringsAsFactors = FALSE)

# Dropping first column (the row names written by R's write.csv)
data <- data[, -1]

# Adding raw payments to the dataset. As in the Python script, the difference
# is taken down the whole column, not within each claim, so a claim's first
# row is compared with the previous claim's last row (negatives are set to 0).
payments <- c(0, diff(data$cumpaid))
payments[is.na(payments)] <- 0
payments[payments < 0] <- 0
data$payments <- payments

# Building the index dataset (claims in order of claim_no, then c ascending)
claims     <- split(data, data$claim_no)
index_data <- as.data.frame(do.call(rbind, lapply(claims, make_index_rows)))
rownames(index_data) <- NULL

# Adding indexes to index set (0-based, matching pandas' index)
index_data$index <- seq_len(nrow(index_data)) - 1

# Adding m(t) and log(m(t)) to index dataset
index_data$m     <- index_data$claim_size / index_data$case_estimate
index_data$log_m <- log(index_data$m)


# Creating dataframe with only censored rows: for each index row, every
# transaction of that claim strictly before the censoring time c
claim_ids     <- sort(unique(data$claim_no))
rows_by_claim <- split(seq_len(nrow(data)), factor(data$claim_no, levels = claim_ids))

box_rows <- mapply(function(claim_no, c) {
  r <- rows_by_claim[[match(claim_no, claim_ids)]]
  r[which(data$txn_time[r] < c)]
}, index_data$claim_no, index_data$c, SIMPLIFY = FALSE)

n_rows <- lengths(box_rows)

databoxes <- data.frame(
  index = rep(index_data$index, n_rows),
  c     = rep(index_data$c, n_rows),
  data[unlist(box_rows), c('claim_no', 'txn_time', 'txn_delay', 'txn_type',
                           'incurred', 'OCL', 'cumpaid', 'multiplier')],
  row.names = NULL
)


# renaming columns
index_data <- rename_cols(index_data, 'c', 'pred_time')
databoxes  <- rename_cols(databoxes, c('c', 'txn_time', 'txn_delay'),
                          c('pred_time', 'cal_time', 'dev_time'))

# Replacing NAs with -1
index_data <- fill_na(index_data)
databoxes  <- fill_na(databoxes)


# converting txn_type into numeric features (is_payment, is_major, is_minor)
databoxes$is_payment <- as.integer(databoxes$txn_type %in% payment_types)
databoxes$is_major   <- as.integer(databoxes$txn_type %in% c('Ma', 'PMa'))
databoxes$is_minor   <- as.integer(databoxes$txn_type %in% c('Mi', 'PMi'))

# rename columns
databoxes  <- rename_cols(databoxes, c('cumpaid', 'OCL'), c('paid', 'ocl'))
index_data <- rename_cols(index_data, c('claim_size', 'incurred'),
                          c('target', 'latest_incurred'))

### TRAIN TEST SPLIT ##########################################################

# splitting into train and test sets by claim number
set.seed(1)
train_prop   <- 0.7
max_claimno  <- max(index_data$claim_no)
max_sequence <- seq_len(max_claimno)

train_id <- sample(max_sequence, floor(train_prop * length(max_sequence)))

train_index <- index_data[index_data$claim_no %in% train_id, ]
test_index  <- index_data[!(index_data$claim_no %in% train_id), ]

train_set <- databoxes[databoxes$claim_no %in% train_id, ]
test_set  <- databoxes[!(databoxes$claim_no %in% train_id), ]

# Splitting test set into test and validation sets
test_claimnos <- unique(test_set$claim_no)

val_id <- test_claimnos[sample.int(length(test_claimnos),
                                   floor(0.5 * length(test_claimnos)))]

val_index  <- test_index[test_index$claim_no %in% val_id, ]
test_index <- test_index[!(test_index$claim_no %in% val_id), ]

val_set  <- test_set[test_set$claim_no %in% val_id, ]
test_set <- test_set[!(test_set$claim_no %in% val_id), ]

### EXPORTING #################################################################

# columns for the different model input versions
v1_set_cols <- c('index', 'claim_no', 'pred_time', 'dev_time', 'cal_time',
                 'paid', 'ocl')
v2_set_cols <- c(v1_set_cols, 'is_payment', 'is_major', 'is_minor',
                 'multiplier')

v1_index_cols <- c('index', 'claim_no', 'pred_time', 'dev_quarter',
                   'occ_quarter', 'target', 'latest_incurred', 'm', 'log_m')
v3_index_cols <- c(v1_index_cols, 'num_payments', 'mean_payments',
                   'var_payments', 'max_payment', 'num_revisions',
                   'num_upward', 'total_variation')

export_version <- function(fp_out, set_cols, index_cols) {
  dir.create(fp_out, recursive = TRUE, showWarnings = FALSE)
  out <- list(train_index = train_index[, index_cols],
              val_index   = val_index[, index_cols],
              test_index  = test_index[, index_cols],
              train_set   = train_set[, set_cols],
              val_set     = val_set[, set_cols],
              test_set    = test_set[, set_cols])
  for (nm in names(out)) {
    write.csv(out[[nm]], paste0(fp_out, nm, '.csv'), row.names = FALSE)
  }
}

# V1
export_version(fp_out_v1, v1_set_cols, v1_index_cols)

# V2 (same index files as V1)
export_version(fp_out_v2, v2_set_cols, v1_index_cols)

# V3 (same set files as V2)
export_version(fp_out_v3, v2_set_cols, v3_index_cols)
