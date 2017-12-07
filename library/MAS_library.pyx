import numpy as np 
import time,sys,os
cimport numpy as np
cimport cython
from libc.math cimport sqrt,pow,sin,cos,floor,fabs


################################################################################
################################# ROUTINES #####################################
# MA(pos,number,BoxSize,MAS='CIC',W=None) ---> main routine
# NGP(pos,number,BoxSize)
# CIC(pos,number,BoxSize)
# TSC(pos,number,BoxSize)
# PCS(pos,number,BoxSize)
# NGPW(pos,number,BoxSize,W)
# CICW(pos,number,BoxSize,W)
# TSCW(pos,number,BoxSize,W)
# PCSW(pos,number,BoxSize,W)
# CIC_interp(pos,density,BoxSize,dens)
# voronoi_NGP_2D(density,pos,mass,volume,x_min,y_min,BoxSize,
#                          particles_per_cell,r_divisions)
# voronoi_RT_2D_periodic(density,pos,mass,radius,x_min,y_min,BoxSize)
# voronoi_RT_2D_no_periodic(density,pos,mass,radius,x_min,y_min,BoxSize)
# SPH_NGP(density,pos,radius,r_bins,part_in_shell,BoxSize,verbose)
# SPH_NGPW(density,pos,radius,W,r_bins,part_in_shell,BoxSize,verbose)
# TO-DO: 2D computations are suboptimal for CIC,TSC and PCS as particles along
# the axis 2 are repeated 2,3 and 4 times, respectively
################################################################################
################################################################################

# This is the main function to use when performing the mass assignment
# pos --------> array containing the positions of the particles: 2D or 3D
# numbers ----> array containing the density field: 2D or 3D
# BoxSize ----> size of the simulation box
# MAS --------> mass assignment scheme: NGP, CIC, TSC or PCS
# W ----------> array containing the weights to be used: 1D array (optional)
# renormalize_2D ---> when computing the density field by reading multiple 
# subfiles, the normalization factor /2.0, /3.0, /4.0 should be added manually
# only at the end, otherwise the results will be incorrect!!
cpdef void MA(pos, number, BoxSize, MAS='CIC', W=None, verbose=False,
              renormalize_2D=True):

    #number of coordinates to work in 2D or 3D
    coord,coord_aux = pos.shape[1], number.ndim 

    # check that the number of dimensions match
    if coord!=coord_aux:
        print 'pos have %d dimensions and the density %d!!!'%(coord,coord_aux)
        sys.exit()

    if verbose:
        if W is None:  print '\nUsing %s mass assignment scheme'%MAS;
        else:          print '\nUsing %s mass assignment scheme with weights'%MAS;
    start = time.clock()
    if coord==3: 
        if   MAS=='NGP' and W is None:  NGP(pos,number,BoxSize)
        elif MAS=='CIC' and W is None:  CIC(pos,number,BoxSize)
        elif MAS=='TSC' and W is None:  TSC(pos,number,BoxSize)
        elif MAS=='PCS' and W is None:  PCS(pos,number,BoxSize)
        elif MAS=='NGP' and W is not None:  NGPW(pos,number,BoxSize,W)
        elif MAS=='CIC' and W is not None:  CICW(pos,number,BoxSize,W)
        elif MAS=='TSC' and W is not None:  TSCW(pos,number,BoxSize,W)
        elif MAS=='PCS' and W is not None:  PCSW(pos,number,BoxSize,W)
        else:
            print 'option not valid!!!';  sys.exit()

    if coord==2:
        number2 = np.expand_dims(number,axis=2)
        if   MAS=='NGP' and W is None:  
            NGP(pos,number2,BoxSize)
        elif MAS=='CIC' and W is None:  
            CIC(pos,number2,BoxSize);
            if renormalize_2D:  number2 /= 2.0
        elif MAS=='TSC' and W is None:  
            TSC(pos,number2,BoxSize);  
            if renormalize_2D:  number2 /= 3.0
        elif MAS=='PCS' and W is None:  
            PCS(pos,number2,BoxSize);
            if renormalize_2D:  number2 /= 4.0
        elif MAS=='NGP' and W is not None:  
            NGPW(pos,number2,BoxSize,W)
        elif MAS=='CIC' and W is not None:  
            CICW(pos,number2,BoxSize,W);
            if renormalize_2D:  number2 /= 2.0
        elif MAS=='TSC' and W is not None:  
            TSCW(pos,number2,BoxSize,W);
            if renormalize_2D:  number2 /= 3.0
        elif MAS=='PCS' and W is not None:  
            PCSW(pos,number2,BoxSize,W); 
            if renormalize_2D:  number2 /= 4.0
        else:
            print 'option not valid!!!';  sys.exit()
        number = number2[:,:,0]
    if verbose:
        print 'Time taken = %.3f seconds\n'%(time.clock()-start)
    

################################################################################
# This function computes the density field of a cubic distribution of particles
# pos ------> positions of the particles. Numpy array
# number ---> array with the density field. Numpy array (dims,dims,dims)
# BoxSize --> Size of the box
@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True) 
cdef void CIC(np.float32_t[:,:] pos, np.float32_t[:,:,:] number, float BoxSize):
        
    cdef int axis,dims,coord
    cdef long i,particles
    cdef float inv_cell_size,dist
    cdef float u[3]
    cdef float d[3]
    cdef int index_u[3]
    cdef int index_d[3]

    # find number of particles, the inverse of the cell size and dims
    particles = pos.shape[0];  coord = pos.shape[1];  dims = number.shape[0]
    inv_cell_size = dims/BoxSize
    
    # when computing things in 2D, use the index_ud[2]=0 plane
    for i in xrange(3):
        index_d[i] = 0;  index_u[i] = 0;  d[i] = 1.0;  u[i] = 1.0

    # do a loop over all particles
    for i in xrange(particles):

        # $: grid point, X: particle position
        # $.........$..X......$
        # ------------>         dist    (1.3)
        # --------->            index_d (1)
        # --------------------> index_u (2)
        #           --->        u       (0.3)
        #              -------> d       (0.7)
        for axis in xrange(coord):
            dist          = pos[i,axis]*inv_cell_size
            u[axis]       = dist - <int>dist
            d[axis]       = 1.0 - u[axis]
            index_d[axis] = (<int>dist)%dims
            index_u[axis] = index_d[axis] + 1
            index_u[axis] = index_u[axis]%dims #seems this is faster

        number[index_d[0],index_d[1],index_d[2]] += d[0]*d[1]*d[2]
        number[index_d[0],index_d[1],index_u[2]] += d[0]*d[1]*u[2]
        number[index_d[0],index_u[1],index_d[2]] += d[0]*u[1]*d[2]
        number[index_d[0],index_u[1],index_u[2]] += d[0]*u[1]*u[2]
        number[index_u[0],index_d[1],index_d[2]] += u[0]*d[1]*d[2]
        number[index_u[0],index_d[1],index_u[2]] += u[0]*d[1]*u[2]
        number[index_u[0],index_u[1],index_d[2]] += u[0]*u[1]*d[2]
        number[index_u[0],index_u[1],index_u[2]] += u[0]*u[1]*u[2]
################################################################################

################################################################################
# This function computes the density field of a cubic distribution of particles
# using weights
# pos ------> positions of the particles. Numpy array
# number ---> array with the density field. Numpy array (dims,dims,dims)
# BoxSize --> Size of the box
# W --------> weights of the particles
@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
cdef void CICW(np.float32_t[:,:] pos, np.float32_t[:,:,:] number, float BoxSize,
               np.float32_t[:] W):

    cdef int axis,dims,coord
    cdef long i,particles
    cdef float inv_cell_size,dist
    cdef float u[3]
    cdef float d[3]
    cdef int index_d[3]
    cdef int index_u[3]
    
    # find number of particles, the inverse of the cell size and dims
    particles = pos.shape[0];  coord = pos.shape[1];  dims = number.shape[0]
    inv_cell_size = dims/BoxSize
    
    # when computing things in 2D, use the index_ud[2]=0 plane
    for i in xrange(3):
        index_d[i] = 0;  index_u[i] = 0;  d[i] = 1.0;  u[i] = 1.0

    # do a loop over all particles
    for i in xrange(particles):

        for axis in xrange(coord):
            dist          = pos[i,axis]*inv_cell_size
            u[axis]       = dist - <int>dist
            d[axis]       = 1.0 - u[axis]
            index_d[axis] = (<int>dist)%dims
            index_u[axis] = index_d[axis] + 1
            index_u[axis] = index_u[axis]%dims #seems this is faster

        number[index_d[0],index_d[1],index_d[2]] += d[0]*d[1]*d[2]*W[i]
        number[index_d[0],index_d[1],index_u[2]] += d[0]*d[1]*u[2]*W[i]
        number[index_d[0],index_u[1],index_d[2]] += d[0]*u[1]*d[2]*W[i]
        number[index_d[0],index_u[1],index_u[2]] += d[0]*u[1]*u[2]*W[i]
        number[index_u[0],index_d[1],index_d[2]] += u[0]*d[1]*d[2]*W[i]
        number[index_u[0],index_d[1],index_u[2]] += u[0]*d[1]*u[2]*W[i]
        number[index_u[0],index_u[1],index_d[2]] += u[0]*u[1]*d[2]*W[i]
        number[index_u[0],index_u[1],index_u[2]] += u[0]*u[1]*u[2]*W[i]
################################################################################

################################################################################
@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
cdef void NGP(np.float32_t[:,:] pos, np.float32_t[:,:,:] number, float BoxSize):

    cdef int axis,dims,coord
    cdef long i,particles
    cdef float inv_cell_size
    cdef int index[3]

    # find number of particles, the inverse of the cell size and dims
    particles = pos.shape[0];  coord = pos.shape[1];  dims = number.shape[0]
    inv_cell_size = dims/BoxSize

    # when computing things in 2D, use the index[2]=0 plane
    for i in xrange(3):  index[i] = 0

    # do a loop over all particles
    for i in xrange(particles):
        for axis in xrange(coord):
            index[axis] = <int>(pos[i,axis]*inv_cell_size + 0.5)
            index[axis] = (index[axis]+dims)%dims
        number[index[0],index[1],index[2]] += 1.0
################################################################################

################################################################################
# This function computes the density field of a cubic distribution of particles
# using weights
# pos ------> positions of the particles. Numpy array
# number ---> array with the density field. Numpy array (dims,dims,dims)
# BoxSize --> Size of the box
# W --------> weights of the particles
@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
cdef void NGPW(np.float32_t[:,:] pos, np.float32_t[:,:,:] number, float BoxSize,
               np.float32_t[:] W):

    cdef int axis,dims,coord
    cdef long i,particles
    cdef float inv_cell_size
    cdef int index[3]

    # find number of particles, the inverse of the cell size and dims
    particles = pos.shape[0];  coord = pos.shape[1];  dims = number.shape[0]
    inv_cell_size = dims/BoxSize

    # when computing things in 2D, use the index[2]=0 plane
    for i in xrange(3):  index[i] = 0

    # do a loop over all particles
    for i in xrange(particles):
        for axis in xrange(coord):
            index[axis] = <int>(pos[i,axis]*inv_cell_size + 0.5)
            index[axis] = (index[axis]+dims)%dims
        number[index[0],index[1],index[2]] += W[i]
################################################################################

################################################################################
# This function computes the density field of a cubic distribution of particles
# pos ------> positions of the particles. Numpy array
# number ---> array with the density field. Numpy array (dims,dims,dims)
# BoxSize --> Size of the box
@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
cdef void TSC(np.float32_t[:,:] pos, np.float32_t[:,:,:] number, float BoxSize):

    cdef int axis, dims, minimum
    cdef int j, l, m, n, coord
    cdef long i, particles
    cdef float inv_cell_size, dist, diff
    cdef float C[3][3]
    cdef int index[3][3]

    # find number of particles, the inverse of the cell size and dims
    particles = pos.shape[0];  coord = pos.shape[1];  dims = number.shape[0]
    inv_cell_size = dims/BoxSize
    
    # define arrays: for 2D set we have C[2,:] = 1.0 and index[2,:] = 0
    for i in xrange(3):
        for j in xrange(3):
            C[i][j] = 1.0;  index[i][j] = 0
            
    # do a loop over all particles
    for i in xrange(particles):

        # do a loop over the axes of the particle
        for axis in xrange(coord):
            dist    = pos[i,axis]*inv_cell_size
            minimum = <int>floor(dist-1.5)
            for j in xrange(3): #only 3 cells/dimension can contribute
                index[axis][j] = (minimum+j+1+dims)%dims
                diff = fabs(minimum + j+1 - dist)
                if diff<0.5:    C[axis][j] = 0.75-diff*diff
                elif diff<1.5:  C[axis][j] = 0.5*(1.5-diff)*(1.5-diff)
                else:           C[axis][j] = 0.0

        for l in xrange(3):  
            for m in xrange(3):  
                for n in xrange(3): 
                    number[index[0][l],index[1][m],index[2][n]] += C[0][l]*C[1][m]*C[2][n]
################################################################################

################################################################################
# This function computes the density field of a cubic distribution of particles
# using weights
# pos ------> positions of the particles. Numpy array
# number ---> array with the density field. Numpy array (dims,dims,dims)
# BoxSize --> Size of the box
# W --------> weights of the particles
@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
cdef void TSCW(np.float32_t[:,:] pos, np.float32_t[:,:,:] number, float BoxSize,
               np.float32_t[:] W):

    cdef int axis,dims,minimum,j,l,m,n,coord
    cdef long i,particles
    cdef float inv_cell_size,dist,diff
    cdef float C[3][3]
    cdef int index[3][3]

    # find number of particles, the inverse of the cell size and dims
    particles = pos.shape[0];  coord = pos.shape[1];  dims = number.shape[0]
    inv_cell_size = dims/BoxSize
    
    # define arrays: for 2D set we have C[2,:] = 1.0 and index[2,:] = 0
    for i in xrange(3):
        for j in xrange(3):
            C[i][j] = 1.0;  index[i][j] = 0
    
    # do a loop over all particles
    for i in xrange(particles):

        # do a loop over the three axes of the particle
        for axis in xrange(coord):
            dist    = pos[i,axis]*inv_cell_size
            minimum = <int>floor(dist-1.5)
            for j in xrange(3): #only 3 cells/dimension can contribute
                index[axis][j] = (minimum+ j+1+ dims)%dims
                diff = fabs(minimum+ j+1 - dist)
                if diff<0.5:    C[axis][j] = 0.75-diff*diff
                elif diff<1.5:  C[axis][j] = 0.5*(1.5-diff)*(1.5-diff)
                else:           C[axis][j] = 0.0

        for l in xrange(3):  
            for m in xrange(3):  
                for n in xrange(3): 
                    number[index[0][l],index[1][m],index[2][n]] += C[0][l]*C[1][m]*C[2][n]*W[i]
################################################################################

################################################################################
# This function computes the density field of a cubic distribution of particles
# pos ------> positions of the particles. Numpy array
# number ---> array with the density field. Numpy array (dims,dims,dims)
# BoxSize --> Size of the box
@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
cdef void PCS(np.float32_t[:,:] pos, np.float32_t[:,:,:] number, float BoxSize):

    cdef int axis,dims,minimum,j,l,m,n,coord
    cdef long i,particles
    cdef float inv_cell_size,dist,diff
    cdef float C[3][4]
    cdef int index[3][4]

    # find number of particles, the inverse of the cell size and dims
    particles = pos.shape[0];  coord = pos.shape[1];  dims = number.shape[0]
    inv_cell_size = dims/BoxSize
        
    # define arrays: for 2D set we have C[2,:] = 1.0 and index[2,:] = 0
    for i in xrange(3):
        for j in xrange(4):
            C[i][j] = 1.0;  index[i][j] = 0

    # do a loop over all particles
    for i in xrange(particles):

        # do a loop over the three axes of the particle
        for axis in xrange(coord):
            dist    = pos[i,axis]*inv_cell_size
            minimum = <int>floor(dist-2.0)
            for j in xrange(4): #only 4 cells/dimension can contribute
                index[axis][j] = (minimum + j+1 + dims)%dims
                diff = fabs(minimum + j+1 - dist)
                if diff<1.0:    C[axis][j] = (4.0 - 6.0*diff*diff + 3.0*diff*diff*diff)/6.0
                elif diff<2.0:  C[axis][j] = (2.0 - diff)*(2.0 - diff)*(2.0 - diff)/6.0
                else:           C[axis][j] = 0.0

        for l in xrange(4):  
            for m in xrange(4):  
                for n in xrange(4): 
                    number[index[0][l],index[1][m],index[2][n]] += C[0][l]*C[1][m]*C[2][n]
################################################################################

################################################################################
# This function computes the density field of a cubic distribution of particles
# using weights
# pos ------> positions of the particles. Numpy array
# number ---> array with the density field. Numpy array (dims,dims,dims)
# BoxSize --> Size of the box
# W --------> weights of the particles
@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
cdef void PCSW(np.float32_t[:,:] pos, np.float32_t[:,:,:] number, float BoxSize,
               np.float32_t[:] W):

    cdef int axis,dims,minimum,j,l,m,n,coord
    cdef long i,particles
    cdef float inv_cell_size,dist,diff
    cdef float C[3][4]
    cdef int index[3][4]

    # find number of particles, the inverse of the cell size and dims
    particles = pos.shape[0];  coord = pos.shape[1];  dims = number.shape[0]
    inv_cell_size = dims/BoxSize

    # define arrays: for 2D set we have C[2,:] = 1.0 and index[2,:] = 0
    for i in xrange(3):
        for j in xrange(4):
            C[i][j] = 1.0;  index[i][j] = 0
    
    # do a loop over all particles
    for i in xrange(particles):

        # do a loop over the three axes of the particle
        for axis in xrange(coord):
            dist    = pos[i,axis]*inv_cell_size
            minimum = <int>floor(dist-2.0)
            for j in xrange(4): #only 4 cells/dimension can contribute
                index[axis][j] = (minimum + j+1 + dims)%dims
                diff = fabs(minimum + j+1 - dist)
                if diff<1.0:    C[axis][j] = (4.0 - 6.0*diff*diff + 3.0*diff*diff*diff)/6.0
                elif diff<2.0:  C[axis][j] = (2.0 - diff)*(2.0 - diff)*(2.0 - diff)/6.0
                else:           C[axis][j] = 0.0

        for l in xrange(4):
            for m in xrange(4):
                for n in xrange(4): 
                    number[index[0][l],index[1][m],index[2][n]] += C[0][l]*C[1][m]*C[2][n]*W[i]
################################################################################

################################################################################
# This function takes a 3D grid called density. The routine finds the CIC 
# interpolated value of the grid onto the positions input as pos
# density --> 3D array with containing the density field
# BoxSize --> Size of the box
# pos ------> positions where the density field will be interpolated
# den ------> array with the interpolated density field at pos
@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
cpdef void CIC_interp(np.ndarray[np.float32_t,ndim=3] density, float BoxSize,
                      np.ndarray[np.float32_t,ndim=2] pos,
                      np.ndarray[np.float32_t,ndim=1] den):

    cdef int axis,dims
    cdef long i,particles
    cdef float inv_cell_size,dist
    cdef float u[3]
    cdef float d[3]
    cdef int index_u[3]
    cdef int index_d[3]
    
    # find number of particles, the inverse of the cell size and dims
    particles = pos.shape[0];  dims = density.shape[0]
    inv_cell_size = dims/BoxSize

    # do a loop over all particles
    for i in xrange(particles):

        # $: grid point, X: particle position
        # $.........$..X......$
        # ------------>         dist    (1.3)
        # --------->            index_d (1)
        # --------------------> index_u (2)
        #           --->        u       (0.3)
        #              -------> d       (0.7)
        for axis in xrange(3):
            dist          = pos[i,axis]*inv_cell_size
            u[axis]       = dist - <int>dist
            d[axis]       = 1.0 - u[axis]
            index_d[axis] = (<int>dist)%dims
            index_u[axis] = index_d[axis] + 1
            index_u[axis] = index_u[axis]%dims #seems this is faster

        den[i] = density[index_d[0],index_d[1],index_d[2]]*d[0]*d[1]*d[2]+\
                 density[index_d[0],index_d[1],index_u[2]]*d[0]*d[1]*u[2]+\
                 density[index_d[0],index_u[1],index_d[2]]*d[0]*u[1]*d[2]+\
                 density[index_d[0],index_u[1],index_u[2]]*d[0]*u[1]*u[2]+\
                 density[index_u[0],index_d[1],index_d[2]]*u[0]*d[1]*d[2]+\
                 density[index_u[0],index_d[1],index_u[2]]*u[0]*d[1]*u[2]+\
                 density[index_u[0],index_u[1],index_d[2]]*u[0]*u[1]*d[2]+\
                 density[index_u[0],index_u[1],index_u[2]]*u[0]*u[1]*u[2]
################################################################################


# This routine computes the 2D density field from a set of voronoi cells that
# have masses and volumes.
@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
cpdef void voronoi_NGP_2D(np.ndarray[np.float64_t,ndim=2] density, 
                          np.ndarray[np.float32_t,ndim=2] pos,
                          np.ndarray[np.float32_t,ndim=1] mass,
                          np.ndarray[np.float32_t,ndim=1] volume,
                          float x_min, float y_min, float BoxSize,
                          long particles_per_cell, int r_divisions):

    cdef float pi = np.pi
    cdef long i, j, k, particles, particles_shell, dims
    cdef double R1, R2, A_shell, dtheta, angle
    cdef np.float32_t[:] R
    cdef np.float32_t[:,:] pos_tracer
    cdef float radius, x, y, inv_cell_size, W, radius_voronoi_cell
    cdef int index_x, index_y

    # verbose
    print 'Finding density field of the voronoi tracers...'
    start = time.time()

    # find the number of particles to analyze and inv_cell_size
    particles     = pos.shape[0]
    dims          = density.shape[0]
    inv_cell_size = dims*1.0/BoxSize

    # compute the number of particles in each shell and the angle between them
    particles_shell = particles_per_cell/r_divisions
    dtheta          = 2.0*pi/particles_shell

    # define the array containing the normalized radii
    R = np.zeros(r_divisions, dtype=np.float32)

    # do a loop over the different shells and compute the mean radii to them
    A_shell, R1 = 4.0*pi/r_divisions, 0.0
    for j in xrange(r_divisions):
        R2 = sqrt(A_shell/(4.0*pi) + R1**2)
        R[j] = 0.5*(R1+R2)
        R1 = R2

    # define and fill the array containing pos_tracer
    pos_tracer = np.zeros((particles_shell,2), dtype=np.float32)
    angle = 0.0
    for i in xrange(particles_shell):
        pos_tracer[i,0] = cos(angle)
        pos_tracer[i,1] = sin(angle)
        angle += dtheta
        
        
        
    # do a loop over all particles
    for i in xrange(particles):
        
        # compute the weight of each voronoi-cell tracer
        W = mass[i]*1.0/(particles_shell*r_divisions)
        
        # compute the "radius" of the voronoi cell
        radius_voronoi_cell = (3.0*volume[i]/(4.0*pi))**(1.0/3.0)

        # do a loop over the different shells of the sphere
        for j in xrange(r_divisions):

            radius = R[j]*radius_voronoi_cell
            
            # do a loop over all particles in the shell
            for k in xrange(particles_shell):
                
                x = pos[i,0] + radius*pos_tracer[k,0]
                y = pos[i,1] + radius*pos_tracer[k,1]
            
                index_x = <int>((x-x_min)*inv_cell_size + 0.5)
                index_y = <int>((y-y_min)*inv_cell_size + 0.5)
                
                density[index_x, index_y] += W

    print 'Time taken = %.3f s'%(time.time()-start)



############################################################################### 
# This routine computes the 2D density field from a set of voronoi cells that
# have masses and radii assuming they represent uniform spheres. A cell that
# intersects with a cell will increase its value by the column density of the 
# cell along the sphere. This routine assumes periodic conditions
@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
cpdef void voronoi_RT_2D_periodic(np.ndarray[np.float64_t,ndim=2] density, 
                                  np.ndarray[np.float32_t,ndim=2] pos,
                                  np.ndarray[np.float32_t,ndim=1] mass,
                                  np.ndarray[np.float32_t,ndim=1] radius,
                                  float x_min, float y_min, float BoxSize):

    start = time.time()
    cdef long particles, i
    cdef int dims, index_x, index_y, index_R, ii, jj, i_cell, j_cell
    cdef float x, y, rho, pi, cell_size, inv_cell_size, radius2
    cdef float dist2, dist2_x

    # find the number of particles and the dimensions of the grid
    particles = pos.shape[0]
    dims      = density.shape[0]
    pi        = np.pi

    # define cell size and the inverse of the cell size
    cell_size     = BoxSize*1.0/dims
    inv_cell_size = dims*1.0/BoxSize

    for i in xrange(particles):

        # find the density of the particle and the square of its radius
        rho     = 3.0*mass[i]/(4.0*pi*radius[i]**3) #h^2 Msun/Mpc^3
        radius2 = radius[i]**2                      #(Mpc/h)^2

        # find cell where the particle center is and its radius in cell units
        index_x = <int>((pos[i,0]-x_min)*inv_cell_size)
        index_y = <int>((pos[i,1]-y_min)*inv_cell_size)
        index_R = <int>(radius[i]*inv_cell_size) + 1

        # do a loop over the cells that contribute in the x-direction
        for ii in xrange(-index_R, index_R+1):
            x       = (index_x + ii)*cell_size + x_min
            i_cell  = ((index_x + ii + dims)%dims)
            dist2_x = (x-pos[i,0])**2 

            # do a loop over the cells that contribute in the y-direction
            for jj in xrange(-index_R, index_R+1):
                y      = (index_y + jj)*cell_size + y_min
                j_cell = ((index_y + jj + dims)%dims)

                dist2 = dist2_x + (y-pos[i,1])**2

                if dist2<radius2:
                    density[i_cell,j_cell] += 2.0*rho*sqrt(radius2 - dist2)
                    
    print 'Time taken = %.2f seconds'%(time.time()-start)
                    
############################################################################### 
# This routine computes the 2D density field from a set of voronoi cells that
# have masses and radii assuming they represent uniform spheres. A cell that
# intersects with a cell will increase its value by the column density of the 
# cell along the sphere. This routine assumes periodic conditions
@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
cpdef void voronoi_RT_2D_no_periodic(np.ndarray[np.float64_t,ndim=2] density, 
                                     np.ndarray[np.float32_t,ndim=2] pos,
                                     np.ndarray[np.float32_t,ndim=1] mass,
                                     np.ndarray[np.float32_t,ndim=1] radius,
                                     float x_min, float y_min, float BoxSize,
                                     verbose=True):

    start = time.time()
    cdef long particles, i
    cdef int dims, index_x, index_y, index_R, ii, jj, i_cell, j_cell
    cdef float x, y, rho, pi, cell_size, inv_cell_size, radius2
    cdef float dist2, dist2_x

    # find the number of particles and the dimensions of the grid
    particles = pos.shape[0]
    dims      = density.shape[0]
    pi        = np.pi

    # define cell size and the inverse of the cell size
    cell_size     = BoxSize*1.0/dims
    inv_cell_size = dims*1.0/BoxSize

    for i in xrange(particles):

        # find the density of the particle and the square of its radius
        rho     = 3.0*mass[i]/(4.0*pi*radius[i]**3) #h^2 Msun/Mpc^3
        radius2 = radius[i]**2                      #(Mpc/h)^2

        # find cell where the particle center is and its radius in cell units
        index_x = <int>((pos[i,0]-x_min)*inv_cell_size)
        index_y = <int>((pos[i,1]-y_min)*inv_cell_size)
        index_R = <int>(radius[i]*inv_cell_size) + 1

        # do a loop over the cells that contribute in the x-direction
        for ii in xrange(-index_R, index_R+1):
            i_cell = index_x + ii
            if i_cell>=0 and i_cell<dims:
                x = i_cell*cell_size + x_min
                dist2_x = (x-pos[i,0])**2 
            else:  continue
                
            # do a loop over the cells that contribute in the y-direction
            for jj in xrange(-index_R, index_R+1):
                j_cell = index_y + jj
                if j_cell>=0 and j_cell<dims:
                    y = j_cell*cell_size + y_min
                else: continue

                dist2 = dist2_x + (y-pos[i,1])**2

                if dist2<radius2:
                    density[i_cell,j_cell] += 2.0*rho*sqrt(radius2 - dist2)
                    
    if verbose:  print 'Time taken = %.2f seconds'%(time.time()-start)


############################################################################### 
# This function generates 2N+1 points in the surface of a sphere of radius 1
# uniformly distributed. See https://arxiv.org/pdf/0912.4540.pdf for details
def sphere_points(N):

    points = np.empty((2*N+1, 3), dtype=np.float32)
    
    i   = np.arange(-N, N+1, 1)
    lat = np.arcsin(2.0*i/(2.0*N+1))
    lon = 2.0*np.pi*i*2.0/(1.0+np.sqrt(5.0))
    
    points[:,0] = np.cos(lat)*np.cos(lon)
    points[:,1] = np.cos(lat)*np.sin(lon)
    points[:,2] = np.sin(lat)
    
    return points

# The standard SPH kernel is: u = r/R, where R is the SPH radius
#                  [ 1-6u^2 + 6u^3  if 0<u<0.5
# W(r) = 8/(pi*R^3)[ 2(1-u)^3       if 0.5<u<1 
#                  [ 0              otherwise
# This function returns 4*pi int_0^r r^2 W(r) dr
# We use this function to split the sphere into shells of equal weight
def sph_kernel_volume(u):
    if u<0.5:    return 32.0/15.0*u**3*(5.0 - 18.0*u**2 + 15.0*u**3)
    elif u<=1.0:  return -1.0/15.0 - 64.0*(u**6/6.0 - 3.0/5.0*u**5 + 3.0/4.0*u**4 -u**3/3.0)
    else:        return 0.0

# This is just a vectorization of the above function
def vsph_kernel_volume(u):
    func = np.vectorize(sph_kernel_volume)
    return func(u)

# This routine computes the density field of a set of particles taking into
# account their physical extent given by its SPH radius
@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
cpdef void SPH_NGP(float[:,:,::1] density, float[:,::1] pos,  
                   float[::1] radius, int r_bins, int part_in_shell,
                   float BoxSize, verbose=True):

    cdef int dims, index_x, index_y, index_z
    cdef long i, j, num, particles, points_sph_sphere
    cdef float R, inv_cell_size, X, Y, Z
    cdef float[::1] r_values
    cdef float[:,::1] points, sph_points

    if verbose:  print 'Findind density field using SPH radii of particles...'

    # determine the mean radii of the radial shells
    radial_bins = np.linspace(0, 1, r_bins+1)
    u_array  = np.linspace(0, 1, 1000)
    V_array  = vsph_kernel_volume(u_array)
    r_values = (np.interp(radial_bins, V_array, u_array)).astype(np.float32)
    for i in xrange(r_bins):
        r_values[i] = 0.5*(r_values[i]+r_values[i+1])

    # generate points uniformly distributed in a sphere
    points = sphere_points(part_in_shell)

    # define the array containing the points in the SPH sphere
    points_sph_sphere = r_bins*points.shape[0]
    sph_points = np.empty((points_sph_sphere, 3), dtype=np.float32)

    # find the position of all particles in the normalized SPH sphere
    num = 0
    for i in xrange(r_bins):
        for j in xrange(points.shape[0]):
            sph_points[num,0] = r_values[i]*points[j,0]
            sph_points[num,1] = r_values[i]*points[j,1]
            sph_points[num,2] = r_values[i]*points[j,2]
            num += 1

    # find the total number of particles
    particles     = pos.shape[0]
    dims          = density.shape[0]
    inv_cell_size = dims*1.0/BoxSize

    # do a loop over all particles
    for i in xrange(particles):
        X = pos[i,0]*inv_cell_size;  Y = pos[i,1]*inv_cell_size;  
        Z = pos[i,2]*inv_cell_size;  R = radius[i]*inv_cell_size

        for j in xrange(points_sph_sphere):
            index_x = <int>(0.5 + (X + R*sph_points[j,0]))
            index_y = <int>(0.5 + (Y + R*sph_points[j,1]))
            index_z = <int>(0.5 + (Z + R*sph_points[j,2]))
            index_x = (index_x+dims)%dims
            index_y = (index_y+dims)%dims
            index_z = (index_z+dims)%dims

            density[index_x, index_y, index_z] += 1.0


# This routine computes the density field of a set of particles taking into
# account their physical extent given by its SPH radius. The contribution
# of each particle is weighted by W
@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
cpdef void SPH_NGPW(float[:,:,::1] density, float[:,::1] pos,
                    float[::1] radius, float[::1] W, int r_bins,
                    int part_in_shell, float BoxSize, verbose=True):

    cdef int dims, index_x, index_y, index_z
    cdef long i, j, num, particles, points_sph_sphere
    cdef float R, inv_cell_size, X, Y, Z
    cdef float[::1] r_values
    cdef float[:,::1] points, sph_points

    if verbose:  print 'Findind density field using SPH radii of particles...'

    # determine the mean radii of the radial shells
    radial_bins = np.linspace(0, 1, r_bins+1)
    u_array  = np.linspace(0, 1, 1000)
    V_array  = vsph_kernel_volume(u_array)
    r_values = (np.interp(radial_bins, V_array, u_array)).astype(np.float32)
    for i in xrange(r_bins):
        r_values[i] = 0.5*(r_values[i]+r_values[i+1])

    # generate points uniformly distributed in a sphere
    points = sphere_points(part_in_shell)

    # define the array containing the points in the SPH sphere
    points_sph_sphere = r_bins*points.shape[0]
    sph_points = np.empty((points_sph_sphere, 3), dtype=np.float32)

    # find the position of all particles in the normalized SPH sphere
    num = 0
    for i in xrange(r_bins):
        for j in xrange(points.shape[0]):
            sph_points[num,0] = r_values[i]*points[j,0]
            sph_points[num,1] = r_values[i]*points[j,1]
            sph_points[num,2] = r_values[i]*points[j,2]
            num += 1

    # find the total number of particles
    particles     = pos.shape[0]
    dims          = density.shape[0]
    inv_cell_size = dims*1.0/BoxSize

    # do a loop over all particles
    for i in xrange(particles):
        X = pos[i,0]*inv_cell_size;  Y = pos[i,1]*inv_cell_size;  
        Z = pos[i,2]*inv_cell_size;  R = radius[i]*inv_cell_size
        weight = W[i]

        for j in xrange(points_sph_sphere):
            index_x = <int>(0.5 + (X + R*sph_points[j,0]))
            index_y = <int>(0.5 + (Y + R*sph_points[j,1]))
            index_z = <int>(0.5 + (Z + R*sph_points[j,2]))
            index_x = (index_x+dims)%dims
            index_y = (index_y+dims)%dims
            index_z = (index_z+dims)%dims

            density[index_x, index_y, index_z] += W[i]


