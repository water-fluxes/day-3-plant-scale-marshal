

getSUF <- function(table_data, table_cond, table_soil, hetero = TRUE, Psi_collar = -15000){
  ####################################################
  #	Calculates Couvreur Macroscopic parameters   #
  ####################################################
  # F?licien Meunier, 06/2017
  # 
  # table_data <- rootsystem2
  # table_cond <- conductivities
  # table_soil <- soil
  # table_data <-  fread("www/rootsystem2.txt", header = T)
  # setwd("../")
  
  # table_cond <- read_csv("www/conductivities.csv")
  
  
  ###################################################################
  #  Connection between basal and Shoot born root with the main axes  #
  ###################################################################
  
  setDT(table_data)
  
  table_data <- table_data %>% 
    mutate(length = sqrt((x2-x1)^2 + (y2-y1)^2 + (z2-z1)^2 )) %>% 
    select(node1ID, node2ID, branchID, x1, y1, z1, x2, y2, z2, radius, length, time, type)
  
  
  
  # Reconnect the nodals
  first <- table_data[table_data$node1ID == 0,]
  nodals_ids <- unique(table_data$branchID[table_data$type == 4 | table_data$type == 5])
  for(no in nodals_ids){
    temp <- table_data[table_data$branchID == no][1]
    connection <- data.frame(node1ID = 0,
                             node2ID = temp$node1ID,
                             branchID = temp$branchID,
                             x1 = first$x1, y1 = first$y1, z1 = first$z1,
                             x2 = temp$x1, y2 = temp$y1, z2 = temp$z1,
                             radius = temp$radius,
                             length = sqrt((first$x1-temp$x1)^2 + (first$y1-temp$y1)^2 + (first$z1-temp$z1)^2 ),
                             time = temp$time,
                             type = temp$type)
    table_data <- rbind(table_data, connection)
  }
  table_data <- table_data[order(table_data$node2ID, decreasing = F),]
  
  
  ####################################################
  # Input data
  ####################################################
  prev <- table_data$node1ID 	  # mother segment
  l <- table_data$length    	  # segment length
  l[l == 0] <- 10e-9
  r <- table_data$radius    	  # segment radius
  z <- table_data$z2           # z-position
  order <- table_data$type      # segment order
  seg_age <- max(table_data$time) - table_data$time     # segment age
  
  tot_length <- sum(l) # total length of the root system
  
  Nseg=length(l)      	  # Total number of segment
  
  Psi_sr_homogeneous <- -300      # Homogeneous soil-root potential 
  Psi_sr_heterogeneous <- -3000   # Heterogeneous soil-root potential 
  
  ####################################################
  # Interpolates kr,kx functions
  
  order_uni=unique(order)
  
  # kr=matrix(10e-3,Nseg,1) # radial conductivity of the segments
  # kx=matrix(1000,Nseg,1) # Axial conductance of the segments
  
  kr=matrix(0,Nseg,1) # radial conductivity of the segments
  kx=matrix(0,Nseg,1) # Axial conductance of the segments
  
  # Linear interpolation
  for ( i in 1:length(order_uni)) {
    
    pos = is.element(order,order_uni[i])
    od <- order_uni[i]
    #if(od == 4) od <- 1 # if nodal, take value for primary
    
    
    x = table_cond$x[table_cond$order_id == od & table_cond$type == "kr"]
    y = table_cond$y[table_cond$order_id == od & table_cond$type == "kr"]
    x <- c(x, 5000)
    y <- c(y, y[length(y)])
    
    xout = data.frame(seg_age[pos])
    temp=data.frame(approx(x,y,xout[,1]))
    kr[pos]=temp[,2]
    
    x = table_cond$x[table_cond$order_id == od & table_cond$type == "kx"]
    y = table_cond$y[table_cond$order_id == od & table_cond$type == "kx"]
    x <- c(x, 5000)
    y <- c(y, y[length(y)])
    temp=data.frame(approx(x,y,xout[,1]))
    kx[pos]=temp[,2]
  }
  
  # Combination of hydraulics and geomitric properties
  kappa=sqrt(2*pi*r*kr*kx)  # kappa
  tau=sqrt(2*pi*r*kr/kx)    # tau
  
  # print(mean(r))
  # print(r[1]) 
  # print(mean(kr))
  # print(kr[1])    
  # print(mean(kx))
  # print(kx[1])  
  # print(mean(kappa))
  # print(kappa[1])
  # print(mean(tau))
  # print(tau[1])
  
  # -----------------------
  # -----------------------
  # -----------------------
  #### HOMOGENEOUS CONDITIONS
  # -----------------------
  # -----------------------
  # -----------------------
  
  Psi_sr= Psi_sr_homogeneous * matrix(1,Nseg,1) # Soil-root potential for each segment
  
  ####################################################
  # Build Matrices
  A = Matrix(c(0),nrow=Nseg+1,ncol=Nseg+1,sparse = TRUE) # Matrix A sparse
  
  j <- 1:Nseg
  i <- prev
  
  rows <- i+1
  columns <- i+1
  values=-kappa/sinh(tau*l)-kappa*tanh(tau*l/2);
  
  rows=c(rows,j+1)
  columns=c(columns,i+1)
  values=c(values,kappa/sinh(tau*l))
  
  rows=c(rows,i+1)
  columns=c(columns,j+1)
  values=c(values,-kappa*tanh(tau*l/2)+kappa/tanh(tau*l))
  
  rows=c(rows,j+1)
  columns=c(columns,j+1)
  values=c(values,-kappa/tanh(tau*l))
  x=mapply(values,FUN=as.numeric)
  
  A <- sparseMatrix(rows, columns, x = x) # Assignates values to specific locations
  a <- A[-1,-1]				    # a matrix = A without the first line and column
  
  # Build Matrix B
  B <- Matrix(c(0),nrow=Nseg+1,ncol=1,sparse = TRUE) # Matrix B sparse
  
  rows <- i+1;
  columns <- matrix(1,Nseg,1)
  values <- -Psi_sr*kappa*tanh(tau*l/2)
  
  rows <- c(rows,j+1)
  columns <- c(columns,matrix(1,Nseg,1))
  values <- c(values,-Psi_sr*kappa*tanh(tau*l/2))
  
  x <- mapply(values,FUN=as.numeric)
  B <- sparseMatrix(rows, columns, x = x) # Assignates values to specific locations
  
  b <- B[-1] # b matrix = B without the first line
  
  prev_collar <- (prev==0)
  
  b[prev_collar] <- b[prev_collar] - (Psi_collar * (kappa[prev_collar] / sinh(tau[prev_collar] * l[prev_collar])))
  
  ####################################################
  # Compute solution
  
  X <- solve(a,b) 		 # a\b
  Psi_basal <- X  		 # Solution = Psi_basal
  prev_temp <- prev	
  prev_temp[prev==0] <- 1;
  Psi_proximal <- Psi_basal[prev_temp] # Psi_proximal = Psi_basal of the mother segment
  Psi_proximal[prev_collar] <- Psi_collar; 
  Jr <- 2*kappa*tanh(tau*l/2)*(Psi_sr-(Psi_proximal+Psi_basal)/2) # Total radial flow
  Jxl <- kappa*((Psi_basal-Psi_sr)/sinh(tau*l)-(Psi_proximal-Psi_sr)/tanh(tau*l)); # Axial flow at the top of the segments
  
  
  remove(a, b, A, B)
  
  # Macroscopic solution
  Tpot=sum(Jr) 		 # Actual transpiration
  SUF=Jr/Tpot  		 # SUF = normalized uptake
  Krs=Tpot/abs(Psi_sr_homogeneous-Psi_collar) # Total root system conductance
  
  Krs_exact <- kappa[1] * tanh(tau[1] * tot_length)
  
  SUF[SUF < 0] <- 10e-10
  
  Tact <- Tpot
  
  # -----------------------
  # -----------------------
  # -----------------------
  #### HETEROGENOUS CONDITIONS
  # -----------------------
  # -----------------------
  # -----------------------
  
  
  if(hetero){
    
    table_soil <- rbind(data.table(id = 0, z = 100, psi = table_soil$psi[1]), table_soil)
    table_soil <- rbind(table_soil, data.table(id = nrow(table_soil)+1, z = -1000, psi = table_soil$psi[nrow(table_soil)]))
    
    Psi_sr <- data.frame(approx(table_soil$z, table_soil$psi, z))[,2]
    
    ####################################################
    # Build Matrices
    A = Matrix(c(0),nrow=Nseg+1,ncol=Nseg+1,sparse = TRUE) # Matrix A sparse
    
    j <- 1:Nseg
    i <- prev
    
    rows <- i+1
    columns <- i+1
    values=-kappa/sinh(tau*l)-kappa*tanh(tau*l/2);
    
    rows=c(rows,j+1)
    columns=c(columns,i+1)
    values=c(values,kappa/sinh(tau*l))
    
    rows=c(rows,i+1)
    columns=c(columns,j+1)
    values=c(values,-kappa*tanh(tau*l/2)+kappa/tanh(tau*l))
    
    rows=c(rows,j+1)
    columns=c(columns,j+1)
    values=c(values,-kappa/tanh(tau*l))
    x=mapply(values,FUN=as.numeric)
    
    A <- sparseMatrix(rows, columns, x = x) # Assignates values to specific locations
    a = A[-1,-1]				    # a matrix = A without the first line and column
    
    # Build Matrix B
    B = Matrix(c(0),nrow=Nseg+1,ncol=1,sparse = TRUE) # Matrix B sparse
    
    rows=i+1;
    columns=matrix(1,Nseg,1)
    values=-Psi_sr*kappa*tanh(tau*l/2)
    
    rows=c(rows,j+1)
    columns=c(columns,matrix(1,Nseg,1))
    values=c(values,-Psi_sr*kappa*tanh(tau*l/2))
    
    x = mapply(values,FUN=as.numeric)
    B <- sparseMatrix(rows, columns, x = x) # Assignates values to specific locations
    
    b=B[-1] # b matrix = B without the first line
    
    prev_collar=(prev==0)
    
    b[prev_collar] = b[prev_collar] - (Psi_collar * (kappa[prev_collar] / sinh(tau[prev_collar] * l[prev_collar])))
    
    ####################################################
    # Compute solution
    
    X=solve(a,b) 		 # a\b
    Psi_basal=X  		 # Solution = Psi_basal
    prev_temp=prev	
    prev_temp[prev==0]=1;
    Psi_proximal=Psi_basal[prev_temp] # Psi_proximal = Psi_basal of the mother segment
    Psi_proximal[prev_collar]=Psi_collar; 
    Jr = 2*kappa*tanh(tau*l/2)*(Psi_sr-(Psi_proximal+Psi_basal)/2) # Total radial flow
    Jxl = kappa*((Psi_basal-Psi_sr)/sinh(tau*l)-(Psi_proximal-Psi_sr)/tanh(tau*l)); # Axial flow at the top of the segments
    
    Tact=sum(Jr) 		 # Actual transpiration
    
    remove(a, b, A, B)
    
  }
  
  
  ####################################################
  return(list(suflog=log10(SUF), 
              suf = SUF, 
              kr = kr, 
              kx = kx, 
              tact = Tact,
              tpot = Tpot,
              krs = Krs, 
              krs_exact = Krs_exact, 
              jr = Jr, 
              psi = Psi_basal, 
              jxl = Jxl,
              psi_soil = Psi_sr,
              psi_collar = Psi_collar, 
              root_system = table_data))
}
