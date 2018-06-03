#!/usr/bin/env Rscript

# Install all the necessary packages
required.packages <- c("crayon","RSQLite","proto","gsubfn","readr","sqldf","stringr")
new.packages <- required.packages[!(required.packages %in% installed.packages()[,"Package"])]
if(length(new.packages)) install.packages(new.packages)
for (p in required.packages) {
  suppressWarnings(library(p,character.only =TRUE))
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

#Check if values are somewhat constant. Output relative stddev
vstats <- function(data,name=substitute(name),show=TRUE) {
    if (show) {
        cat("Value statistics:",name,"MIN:",min(data))
        cat(" MAX: ",max(data),"MEAN:",mean(data),"MEDIAN:",median(data),"STDEV:",sd(data)," (",sd(data)/mean(data)*100,"%)\n")
    }
    if (mean(data) == 0) {
            return(0)
    } else {
        return(sd(data)/mean(data))
    }
}

print_eqn <- function(sum, prefix = "", mape=NA, returnResult=FALSE, statistics=TRUE) {
    ret <- ""
    for (r in rownames(coef(sum))[2:length(rownames(coef(sum)))]) {
        ret <- paste0(ret,coef(sum)[r,"Estimate"])
        for (prod in strsplit(r,":")[[1]]) {
            ret <- paste0(ret," * ")
            if (substr(prod,1,4) == "poly") {
                elem <- strsplit(sub("poly\\(([^,]+), [^\\)]+\\)([0-9]*)","\\1,\\2",prod, perl=TRUE),",")[[1]]
                ret <- paste0(ret,prefix,elem[1])
                ret <- paste0(ret,ifelse(elem[2] > 1,paste("**",elem[2],sep=""),""))
            } else {
                ret <- paste0(ret,prefix,prod)
            }
        }
        ret <- paste0(ret," + ")
    }
    ret <- paste0(ret,coef(sum)["(Intercept)","Estimate"])

    colors = c("green","yellow","white","magenta","red")
    thresholds = c(0.9,0.8,0.7,0.6,0.0)
	if (statistics) {
		cat(ret," [R² =",colorprint(sum$adj.r.squared,thresholds,colors,TRUE))
	    if (! is.na(mape)) {
	        cat(", MAPE =",colorprint(mape,thresholds=c(0.05,0.07,0.1,0.15,1.0),colors,FALSE))
    	}
	    cat("]\n")
	} else {
		cat(ret)
	}
    if (returnResult) return(ret)
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
args <- commandArgs(trailingOnly=TRUE)
if (length(args) < 2) {
    args[2] = "eris.csv"
}
if (length(args) < 1 || is.na(args[1])) {
    args[1] = "bench.csv"
}

# Readin the data
bench <- read_delim(args[1], ";", escape_double = FALSE, trim_ws = TRUE, col_types = cols(`cpu-cycles`="d", `cpu-cycles-ref`="d", instructions="d", `branch-events`="d", `cache-events`="d", `memory-events`="d", `avx-events`="d"))
eris <- read_delim(args[2], ";", escape_double = FALSE, trim_ws = TRUE, col_types = cols(`cpu-cycles`="d", `cpu-cycles-ref`="d", instructions="d", `branch-events`="d", `cache-events`="d", `memory-events`="d", `avx-events`="d"))


mape_threshold <- Sys.getenv("MAPE_THRESHOLD",unset=0.05)

pre <- NROW(bench)
if (Sys.getenv("ERIS_MERGE",unset="N") != "N") {
    cat(style("Mergin ERIS data into calibration data","red"),"\n")
    cE <- colnames(eris)
    cB <- colnames(bench)
    additional <- cE[!cE %in% cB]
    cat("Removing ",paste(additional),"\n")
    bench <- rbind(bench,eris[,-which(names(eris) %in% additional)] )
}
cat("Added",NROW(bench)-pre,"rows\n")

# Do some additional filtering on the data
cat("Filtering data\n")

prefilter <- Sys.getenv("PREFILTER",unset=NA)
if (!is.na(prefilter)) {
    filter <- str_replace(prefilter, "<data>", "bench")
    bench <- sqldf(filter)
}

benches <- Sys.getenv("BENCHES",names=TRUE,unset=NA)
if (!is.na(benches)) {
    benches <- unlist(strsplit(benches,","))
} else {
    benches <- unlist(sqldf("SELECT DISTINCT bench FROM bench")["bench"])
}

benches_exclude <- Sys.getenv("BENCHES_EXCLUDE",names=TRUE,unset=NA)
if (!is.na(benches_exclude)) {
    benches <- setdiff(benches,unlist(strsplit(benches_exclude,",")))
}
bench <- sqldf(paste0("SELECT * FROM bench WHERE bench IN (",paste(sprintf("'%s'",benches),collapse=","),")"))
cat("Removed ",pre-NROW(bench)," of ",pre," entries from bench data\n")

pre <- NROW(eris)
prefilter <- Sys.getenv("ERIS_PREFILTER",unset=NA)
if (!is.na(prefilter)) {
    filter <- str_replace(prefilter, "<data>", "eris")
    eris <- sqldf(filter)
}
eris_benches <- Sys.getenv("ERIS_BENCHES",names=TRUE,unset=NA)
if (!is.na(eris_benches)) {
    eris_benches <- unlist(strsplit(eris_benches,","))
} else {
    eris_benches <- unlist(sqldf("SELECT DISTINCT bench FROM eris")["bench"])
}
eris <- sqldf(paste0("SELECT * FROM eris WHERE bench IN (",paste(sprintf("'%s'",eris_benches),collapse=","),")"))
cat("Removed ",pre-NROW(eris)," of ",pre," entries from ERIS data\n")

# Prepare the data
bench <- within(bench, {
    IPC <- instructions/(`cpu-cycles`/cpus)
    ht <- ifelse(ht == "enable", 1, 0)

    # 'cache-events' counts everything that contains the cache, but we are only interested in cache hits
    `cache-hits` <- `cache-events` - `memory-events`

    # calculate the heaviness of the applications
    memory_heaviness <- `memory-events`/instructions
    nomemory_heaviness <- 1-memory_heaviness
    cache_heaviness <- `cache-hits`/instructions
    avx_heaviness <- `avx-events`/instructions
    branch_heaviness <- `branch-events`/instructions
    compute_heaviness <- (instructions - `cache-hits` - `memory-events` - `avx-events` - `branch-events`)/instructions

    # calculate the power consumption
    power_ram <- `power/energy-ram/`/`t_diff`
    power_cores <- `power/energy-cores/`/`t_diff`
    power_pkg <- `power/energy-pkg/`/`t_diff`
})

eris <- within(eris, {
    IPC <- instructions/(`cpu-cycles`/cpus)
    ht <- ifelse(ht == "enable", 1, 0)

    # 'cache-events' counts everything that contains the cache, but we are only interested in cache hits
    `cache-hits` <- `cache-events` - `memory-events`

    # calculate the heaviness of the applications
    memory_heaviness <- `memory-events`/instructions
    nomemory_heaviness <- 1-memory_heaviness
    cache_heaviness <- `cache-hits`/instructions
    avx_heaviness <- `avx-events`/instructions
    branch_heaviness <- `branch-events`/instructions
    compute_heaviness <- (instructions - `cache-hits` - `memory-events` - `avx-events` - `branch-events`)/instructions

    # calculate the power consumption
    power_ram <- `power/energy-ram/`/`t_diff`
    power_cores <- `power/energy-cores/`/`t_diff`
    power_pkg <- `power/energy-pkg/`/`t_diff`
    tps <- `Tasks.Finished`/`t_diff`
    ipt <- instructions/`Tasks.Finished`
})


# Generate the models
m_IPC <- lm(IPC ~
#Complex Model. Uncomment to use            
                poly(memory_heaviness,2,raw=TRUE)*cpus*freq*ht +
                poly(cache_heaviness,2,raw=TRUE)*cpus*freq*ht +
                poly(compute_heaviness,2,raw=TRUE)*cpus*freq*ht +
                poly(avx_heaviness,2,raw=TRUE)*cpus*freq*ht 
            ,data=bench)
sm_IPC <- summary(m_IPC)
#print(sm_IPC)

m_power_cores <- lm(power_cores ~
                nomemory_heaviness*poly(freq,2,raw=TRUE)*cpus*IPC*avx_heaviness*compute_heaviness#*cache_heaviness
#                avx_heaviness*freq*cpus
#                IPC +
#                poly(freq,3,raw=TRUE) +
#                cpus
#                ht,
            ,data=bench)
sm_power_cores <- summary(m_power_cores)
#print(sm_power_cores)

m_power_ram <- lm(power_ram ~
                poly(memory_heaviness,2,raw=TRUE)*IPC *
                 freq*cpus
            ,data=bench)
sm_power_ram <- summary(m_power_ram)
#print(sm_power_ram)

m_power <- lm(power_pkg ~
                memory_heaviness*poly(freq,2,raw=TRUE)*poly(cpus,2,raw=TRUE)*IPC*avx_heaviness*compute_heaviness#*cache_heaviness
#                poly(freq,3,raw=TRUE) +
#                cpus# +
#                ht
            ,data=bench)
sm_power <- summary(m_power)
#print(sm_power)

#Solve it
bench <- within(bench, {
    IPC_modeled <- solve_eqn(sm_IPC, memory_heaviness=memory_heaviness, cache_heaviness=cache_heaviness, ht=ht, freq=freq, compute_heaviness=compute_heaviness, avx_heaviness=avx_heaviness, cpus=cpus)
    IPC_abserr_rel <- abs(IPC_modeled - IPC) / IPC
    power_pkg_modeled <- solve_eqn(sm_power, IPC=IPC_modeled, freq=freq, ht=ht, cpus=cpus,memory_heaviness=memory_heaviness,avx_heaviness=avx_heaviness,cache_heaviness=cache_heaviness,compute_heaviness=compute_heaviness,nomemory_heaviness=nomemory_heaviness)
    power_pkg_ripc_modeled <- solve_eqn(sm_power, IPC=IPC, freq=freq, ht=ht, cpus=cpus,memory_heaviness=memory_heaviness,avx_heaviness=avx_heaviness,cache_heaviness=cache_heaviness,compute_heaviness=compute_heaviness,nomemory_heaviness=nomemory_heaviness)
    power_ram_modeled <- solve_eqn(sm_power_ram, IPC=IPC_modeled, freq=freq, ht=ht, cpus=cpus,memory_heaviness=memory_heaviness)
    power_ram_ripc_modeled <- solve_eqn(sm_power_ram, IPC=IPC, freq=freq, ht=ht, cpus=cpus,memory_heaviness=memory_heaviness)
    power_cores_modeled <- solve_eqn(sm_power_cores, IPC=IPC_modeled, freq=freq, ht=ht, cpus=cpus,nomemory_heaviness=nomemory_heaviness,avx_heaviness=avx_heaviness,cache_heaviness=cache_heaviness,compute_heaviness=compute_heaviness)
    power_cores_ripc_modeled <- solve_eqn(sm_power_cores, IPC=IPC, freq=freq, ht=ht, cpus=cpus,nomemory_heaviness=nomemory_heaviness,avx_heaviness=avx_heaviness,cache_heaviness=cache_heaviness,compute_heaviness=compute_heaviness)
})

calc_abserrs <- function(df,...) {
    for (i in list(...)) {
        eval.parent(substitute(df[paste0(i,"_abserr_rel")] <- abs(df[paste0(i,"_modeled")] - df[i])/df[i]))
        eval.parent(substitute(df[paste0(i,"_ripc_abserr_rel")] <- abs(df[paste0(i,"_ripc_modeled")] - df[i])/df[i]))
    }
}
calc_abserrs(bench,"power_pkg","power_ram","power_cores")



cat("IPC = "); print_eqn(sm_IPC,mape=mean(bench$IPC_abserr_rel))
cat("P_pkg = "); print_eqn(sm_power,mape=mean(bench$power_pkg_ripc_abserr_rel))
cat("P_ram = "); print_eqn(sm_power_ram,mape=mean(bench$power_ram_ripc_abserr_rel))
cat("P_cores = "); print_eqn(sm_power_cores,mape=mean(bench$power_cores_ripc_abserr_rel))

colors = c("green","yellow","white","magenta","red")
thresholds=c(0.05,0.07,0.1,0.15,1.0)

cat("\n== Results for NPB bechmarks ==\n")
cat(style("columns denoted with ' use real IPC values, not modeled ones\n\n","green"))

metrics <- c("IPC","P_PKG","P_CORES","P_RAM","P_PKG'","P_CORES'","P_RAM'")
metric_columns <- c("IPC_abserr_rel","power_pkg_abserr_rel","power_cores_abserr_rel","power_ram_abserr_rel",
                "power_pkg_ripc_abserr_rel","power_cores_ripc_abserr_rel","power_ram_ripc_abserr_rel")

print_eval <- function(dataframe,benches,metrics,metric_columns) {
    cat('Datapoints as basis for models and evaluation: ',nrow(dataframe),"\n")
    prstr <- max(nchar(benches),nchar("MAPE (all)"))
    cat(rep(" ",prstr+2),sep="")
    for (m in metrics) {
        cat(sprintf(" %-8s",m))
    }
    cat("\n")

    for (b in benches) {
        cat(sprintf("%-*s:",prstr,b))
        for (m in metric_columns) {
            cat(" ",colorprint(sprintf("%7s",sprintf("%2.4f",mean(sqldf(paste('select * from ',substitute(dataframe),' where bench == "',b,'"',sep=""))[[m]]))),thresholds,colors,FALSE))
        }
        cat("\n")
    }
    cat(sprintf("%-*s:",prstr,"MAPE (all)"))
    for (m in metric_columns) {
        cat(" ",colorprint(sprintf("%7s",sprintf("%2.4f",mean(dataframe[[m]]))),thresholds,colors,FALSE))
    }
    cat("\n")
}

print_params <- function(model) {
    rns <- rownames(attr(model$terms,"factors"))[c(-1)]
	ret <- ""
	for (rn in rns) {
		if (substr(rn,1,4) == "poly") {
			 elem <- strsplit(sub("poly\\(([^,]+), [^\\)]+\\)","\\1",rn, perl=TRUE),",")[[1]]
			 ret <- paste0(ret,elem[1],", ")
		 } else {
			 ret <- paste0(ret,rn,", ")
		}
	}
	ret <- substr(ret,1,nchar(ret)-2)
	cat(ret)
}

print_eval(bench,benches,metrics,metric_columns)

# Solve it for eris
eris <- within(eris, {
    IPC_modeled <- solve_eqn(sm_IPC, memory_heaviness=memory_heaviness, cache_heaviness=cache_heaviness, ht=ht, freq=freq, compute_heaviness=compute_heaviness, avx_heaviness=avx_heaviness, cpus=cpus)
    IPC_abserr_rel <- abs(IPC_modeled - IPC) / IPC
    power_pkg_modeled <- solve_eqn(sm_power, IPC=IPC_modeled, freq=freq, ht=ht, cpus=cpus,memory_heaviness=memory_heaviness,avx_heaviness=avx_heaviness,cache_heaviness=cache_heaviness,compute_heaviness=compute_heaviness,nomemory_heaviness=nomemory_heaviness)
    power_pkg_ripc_modeled <- solve_eqn(sm_power, IPC=IPC, freq=freq, ht=ht, cpus=cpus,memory_heaviness=memory_heaviness,avx_heaviness=avx_heaviness,cache_heaviness=cache_heaviness,compute_heaviness=compute_heaviness,nomemory_heaviness=nomemory_heaviness)
    power_ram_modeled <- solve_eqn(sm_power_ram, IPC=IPC_modeled, freq=freq, ht=ht, cpus=cpus,memory_heaviness=memory_heaviness)
    power_ram_ripc_modeled <- solve_eqn(sm_power_ram, IPC=IPC, freq=freq, ht=ht, cpus=cpus,memory_heaviness=memory_heaviness)
    power_cores_modeled <- solve_eqn(sm_power_cores, IPC=IPC_modeled, freq=freq, ht=ht, cpus=cpus,nomemory_heaviness=nomemory_heaviness,avx_heaviness=avx_heaviness,cache_heaviness=cache_heaviness,compute_heaviness=compute_heaviness)
    power_cores_ripc_modeled <- solve_eqn(sm_power_cores, IPC=IPC, freq=freq, ht=ht, cpus=cpus,nomemory_heaviness=nomemory_heaviness,avx_heaviness=avx_heaviness,cache_heaviness=cache_heaviness,compute_heaviness=compute_heaviness)
})
calc_abserrs(eris,"power_pkg","power_ram","power_cores")


cat("\n== Results for ERIS ==\n")
vmetrics <- c("memory","avx","cache","compute","nomemory","branch")

prstr <- max(nchar(benches),nchar("heaviness stableness"))
cat("heaviness stddev (rel)",rep(" ",prstr+2-nchar("heaviness stddev (rel)")),sep="")
for (m in vmetrics) {
    cat(sprintf(" %-10s",m))
}
cat("ipt\n")
eris_model <- data.frame(matrix(ncol=length(vmetrics)+1,nrow=0))
colnames(eris_model) <- c(paste0(vmetrics,"_heaviness"),"ipt")

for (b in eris_benches) {
    cat(sprintf("%-*s:",prstr,b))
    for (m in vmetrics)  {
        vals <- sqldf(paste0('select ',m,'_heaviness as v from eris where bench="',b,'"'))$v
        stats <- vstats(vals,m,show=FALSE)
        str <- colorprint(sprintf("%9s",sprintf("%2.4f",stats)),thresholds,colors,FALSE)
        if (stats < mape_threshold) {
            cat(" ",underline(str))
            eris_model[b,paste0(m,"_heaviness")] = mean(vals)
        } else {
            cat(" ",str)
        }
    }
    vals <- sqldf(paste0('select ipt as v from eris where bench="',b,'"'))$v
    stats <- vstats(vals,"ipt",show=FALSE)
    str <- colorprint(sprintf("%9s",sprintf("%2.4f",stats)),thresholds,colors,FALSE)
    if (stats < mape_threshold) {
        cat(" ",underline(str))
        eris_model[b,"ipt"] = mean(vals)
    } else {
        cat(" ",sprintf("%9s",str))
    }
    cat("\n")
}

for (b in eris_benches) {
    data <- sqldf(paste0('select * from eris where bench = "',b,'"'))
    for (m in c(paste0(vmetrics,"_heaviness"),"ipt")) {
#    for (m in c("memory_heaviness","avx_heaviness","cache_heaviness")) {
        if (is.na(eris_model[b,m])) {
            if (min(data[[m]]) == 0 && max(data[[m]]) == 0) {
                cat(paste0(b,":",m," = ",style("not applicable. No such instructions","red")),"\n")
            } else if (max(data[[m]] < 1e-10)) {
                cat(paste0(b,":",m," = ",style("not applicable. Only trace amounts of such instructions (less than 1e-10 per instruction). Using as 0","red")),"\n")
                eris_model[b,m] <- 0
            } else {
                sm <- summary(lm(get(m) ~ poly(cpus,2,raw=TRUE),data=data))
                data <- within(data,modeled <- solve_eqn(sm, cpus=cpus))
                mape <- mean(abs(data$modeled-data[[m]])/data[[m]])
                cat(paste0(b,":",m," = ")); ret <- print_eqn(sm,mape=mape,returnResult=TRUE)
                if (mape < mape_threshold) {
                    eris_model[b,m] <- ret
                }
            }
        }
    }
}

print_eval(eris,eris_benches,metrics,metric_columns)

cat("Eris model parameters:\n",rep("=",20),sep="","\n")
for (n in rownames(eris_model)) {
    cat("\n")
    print(t(eris_model[n,]))
}
#print(transform(eris_model))


write.csv(bench, "r_data.csv")
write.csv(eris, "r_eris_data.csv")

cat0("Writing Hardware Model to ",style("hardware.py","green"),"\n")

sink("hardware.py")
create_lambda <- function(model, name, classMember=FALSE) {
	cat(name,"= lambda "); print_params(model); cat(": "); 
	if (classMember) cat("self, ")
	print_eqn(summary(model),statistics=FALSE); cat("\n")
}

create_lambda(m_IPC,"IPC")
create_lambda(m_power,"P_PKG")
create_lambda(m_power_cores,"P_Cores")
create_lambda(m_power_ram,"P_Ram")
sink()

cat0("Writing Eris Model to ",style("eris.py","green"),"\n")
sink("eris.py")
cat("class Eris:\n\n")
cat("\tdef __init__(self,cpus):\n")
cat("\t\tself.cpus = cpus\n\n")
cat("\tdef benchmarks(self,name):\n")
first <- TRUE
for (b in rownames(eris_model)) {
    if (first) {
        cat("\t\t")
        first=FALSE
    } else {
        cat("\t\tel")
    }
	cat0("if (name == \"",b,"\"):\n")
    cat0("\t\t\treturn {\n")
	for (m in colnames(eris_model)) {
		if (grepl("cpus",eris_model[b,m],fixed=TRUE)) {
			cat0("\t\t\t\t\"",m,"\": lambda:",gsub("cpus","self.cpus",eris_model[b,m]),",\n")
		} else {
			cat0("\t\t\t\t\"",m,"\": lambda:",eris_model[b,m],",\n")
		}
	}
	cat("\t\t\t}\n")
}
sink()
cat0("We are done. All are happy :)\n",style("BYE!\n","green"))
