#!/usr/bin/env Rscript

# Install all the necessary packages
required.packages <- c("crayon","RSQLite","proto","gsubfn","readr","sqldf")
new.packages <- required.packages[!(required.packages %in% installed.packages()[,"Package"])]
if(length(new.packages)) install.packages(new.packages)
for (p in required.packages) {
  library(p,character.only =TRUE)
}

# Helper functions
colorprint <- function(val, thresholds, colors, greater = TRUE) {
    stopifnot(length(thresholds)==length(colors))
    if (is.na(val) || is.nan(val) || is.infinite(val))
        return(style(toString(val),"red"))

    for (i in 1:length(colors)) {
        if (greater) {
            if (val > thresholds[i]) {
                return(style(toString(val),colors[i]))
            }
        } else {
            if (val < thresholds[i]) {
                return(style(toString(val),colors[i]))
            }
        }
    }

    # We are outside of the defined thresholds
    return(val)
}

print_eqn <- function(sum, prefix = "") {
    for (r in rownames(coef(sum))[2:length(rownames(coef(sum)))]) {
        cat(coef(sum)[r,"Estimate"])
        for (prod in strsplit(r,":")[[1]]) {
            cat(" * ")
            if (substr(prod,1,4) == "poly") {
                elem <- strsplit(sub("poly\\(([^,]+), [^\\)]+\\)([0-9]*)","\\1,\\2",prod, perl=TRUE),",")[[1]]
                cat(prefix,elem[1],sep="")
                cat(ifelse(elem[2] > 1,paste("**",elem[2],sep=""),""))
            } else {
                cat(prefix,prod,sep="")
            }
        }
        cat(" + ",sep="")
    }
    cat(coef(sum)["(Intercept)","Estimate"])

    colors = c("green","yellow","white","magenta","red")
    thresholds = c(0.9,0.8,0.7,0.6,0.0)
    cat(" [R² =",colorprint(sum$adj.r.squared,thresholds,colors,TRUE),"]\n")
}

solve_eqn <- function(sum,...) {
    tot_sum = 0
    for (r in rownames(coef(sum))[2:length(rownames(coef(sum)))]) {
        curval <- coef(sum)[r,"Estimate"]
        for (prod in strsplit(r,":")[[1]]) {
            if (substr(prod,1,4) == "poly") {
                elem <- strsplit(sub("poly\\(([^,]+), [^\\)]+\\)([0-9]*)","\\1,\\2",prod, perl=TRUE),",")[[1]]
                if (elem[[1]] %in% names(list(...)))
                    curval <- curval * (list(...)[[elem[1]]] ^ as.numeric(elem[2]))
                else
                    cat("Missing argument to solve_eqn: ", elem[[1]], "\n")
            } else {
                if (prod %in% names(list(...)))
                    curval <- curval * list(...)[[prod]]
                else
                    cat("Missing argument to solve_eqn: ", prod, "\n")
            }
        }
        tot_sum <- tot_sum + curval
    }

    tot_sum <- tot_sum + coef(sum)["(Intercept)","Estimate"]
    return(tot_sum)
}

# Main
args = commandArgs(trailingOnly=TRUE)
if (length(args) == 0) {
    args[1] = "bench.csv"
}
bench <- read_delim(args[1], ";", escape_double = FALSE, trim_ws = TRUE,col_types = cols(`cpu-cycles`="d", `cpu-cycles-ref`="d", instructions="d", `branch-events`="d", `cache-events`="d", `memory-events`="d", `avx-events`="d"))

# Select benches from environment variable 'BENCHES' if applicable
benches <- Sys.getenv("BENCHES",names=TRUE,unset=NA)
if (!is.na(benches)) {
    benches <- unlist(strsplit(benches,","))
    bench <- sqldf(paste0("SELECT * FROM bench WHERE bench IN (",paste(sprintf("'%s'",benches),collapse=","),")"))
} else {
    benches <- unlist(sqldf("SELECT DISTINCT bench FROM bench")["bench"])
}

bench <- within(bench, {
    IPC <- instructions/`cpu-cycles`
    ht <- ifelse(ht == "enable", 1, 0)

    # 'cache-events' counts everything that contains the cache, but we are only interested in cache hits
    `cache-hits` <- `cache-events` - `memory-events`

    # calculate the heaviness of the applications
    memory_heaviness <- `memory-events`/instructions
    cache_heaviness <- `cache-hits`/instructions
    avx_heaviness <- `avx-events`/instructions
    branch_heaviness <- `branch-events`/instructions
    compute_heaviness <- (instructions - `cache-hits` - `memory-events` - `avx-events` - `branch-events`)/instructions

    # calculate the power consumption
    power_ram <- `power/energy-ram/`/`t_diff`
    power_cores <- `power/energy-cores/`/`t_diff`
    power_pkg <- `power/energy-pkg/`/`t_diff`
})

m_IPC <- lm(IPC ~
                memory_heaviness +
                poly(cache_heaviness,3,raw=TRUE) +
                poly(compute_heaviness,3,raw=TRUE) +
                poly(avx_heaviness,3,raw=TRUE) +
                poly(freq,3,raw=TRUE) +
                ht,
            data=bench)
sm_IPC <- summary(m_IPC)
print(sm_IPC)

m_power <- lm(power_pkg ~
                poly(IPC,3,raw=TRUE) +
                poly(freq,3,raw=TRUE) +
                poly(cpus,3,raw=TRUE) +
                ht,
            data=bench)
sm_power <- summary(m_power)
print(sm_power)

#Solve it
bench <- within(bench, {
    IPC_modeled <- solve_eqn(sm_IPC, memory_heaviness=memory_heaviness, cache_heaviness=cache_heaviness, ht=ht, freq=freq, compute_heaviness=compute_heaviness, avx_heaviness=avx_heaviness)
    IPC_abserr_rel <- abs(IPC_modeled - IPC) / IPC
    power_modeled <- solve_eqn(sm_power, IPC=IPC_modeled, freq=freq, ht=ht, cpus=cpus)
    power_abserr_rel <- abs(power_modeled - power_pkg) / power_pkg
})

print_eqn(sm_IPC)
print_eqn(sm_power)

colors = c("green","yellow","white","magenta","red")
thresholds=c(0.02,0.05,0.1,0.2,1.0)

for (b in benches) {
    cat("MAPE IPC (",b,"): ",colorprint(mean(sqldf(paste('select * from bench where bench == "',b,'"',sep=""))$IPC_abserr_rel),thresholds,colors,FALSE),"\n")
}
cat("MAPE IPC: ",colorprint(mean(bench$IPC_abserr_rel),thresholds,colors,FALSE),"\n")
cat("MAPE Power: ",colorprint(mean(bench$power_abserr_rel),thresholds,colors,FALSE),"\n")
