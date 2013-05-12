import numpy as np
import readsnap
import readsubf
import sys
import time
import random

################################### INPUT #######################################
### SNAPSHOTS ###
#snapshot_fname='/data1/villa/b500p512nu0z99tree/snapdir_017/snap_017'
#groups_fname='/home/villa/data1/b500p512nu0z99tree'
#groups_number=17

#snapshot_fname='/data1/villa/b500p512nu0.3z99/snapdir_017/snap_017'
#groups_fname='/data1/villa/b500p512nu0.3z99'
#groups_number=17

snapshot_fname='/data1/villa/b500p512nu0.6z99np1024tree/snapdir_017/snap_017'
groups_fname='/home/villa/data1/b500p512nu0.6z99np1024tree'
groups_number=17

### HALO CATALOGUE PARAMETERS ###
mass_interval=True 
min_mass=2e2 #in units of 1e10 Msun
max_mass=2e5 #in units of 1e10 Msun

threhold=1e-3 #accept values if relative error smaller than this

### HOD PARAMETERS ###
fiducial_density=0.00111 #mean number density for galaxies with Mr<-21
M1=8e13
alpha=1.4
#################################################################################

#read the header and obtain the boxsize
head=readsnap.snapshot_header(snapshot_fname)
BoxSize=head.boxsize

#read positions and IDs of DM particles: sort the IDs array
DM_pos=readsnap.read_block(snapshot_fname,"POS ",parttype=1,verbose=False)
DM_ids=readsnap.read_block(snapshot_fname,"ID  ",parttype=1,verbose=False)
sorted_ids=DM_ids.argsort(axis=0)
#the particle whose ID is N is located in the position sorted_ids[N]
#i.e. DM_ids[sorted_ids[N]]=N
#the position of the particle whose ID is N would be:
#DM_pos[sorted_ids[N]]

#read the IDs of the particles belonging to the CDM halos
halos_ID=readsubf.subf_ids(groups_fname, groups_number,0, 0, swap = False, verbose = False, long_ids = True, read_all = True)
IDs=halos_ID.SubIDs
del halos_ID

#read CDM halos information
halos=readsubf.subfind_catalog(groups_fname,groups_number,group_veldisp=True,masstab=True,long_ids=True,swap=False)
if mass_interval:
    a=halos.group_m_tophat200>min_mass
    b=halos.group_m_tophat200<max_mass
    c=a*b
    halos_indexes=np.where(c==True)[0]
    del a,b,c
halos_pos=halos.group_pos
halos_mass=halos.group_m_tophat200*1e10 #masses in Msun/h
halos_radius=halos.group_r_tophat200
halos_len=halos.group_len
halos_offset=halos.group_offset
del halos
print ' '
print 'total halos found=',len(halos_pos)
print 'halos number density=',len(halos_pos)/(BoxSize*1e-3)**3

#work with the halos in the given mass range 
halo_mass=halos_mass[halos_indexes]
halo_pos=halos_pos[halos_indexes]
halo_radius=halos_radius[halos_indexes]
halo_len=halos_len[halos_indexes]
halo_offset=halos_offset[halos_indexes]

##### COMPUTE Mmin GIVEN M1 & alpha #####
max_iterations=20 #maximum number of iterations
Mmin2=max_mass*1e10; Mmin1=min_mass*1e10 #max_mass|min_mass in 1e10 Msun/h units

i=0
while (i<max_iterations):
    Mmin=0.5*(Mmin2+Mmin1) #estimation of the HOD parameter Mmin

    total_galaxies=0
    inside=np.where(halo_mass>Mmin)[0]
    mass=halo_mass[inside] #only halos with M>Mmin have central and satellites

    total_galaxies=mass.shape[0]+np.sum((mass/M1)**alpha)
    mean_density=total_galaxies*1.0/(BoxSize*1e-3)**3

    if (np.absolute((mean_density-fiducial_density)/fiducial_density)<1e-3):
        i=max_iterations
    elif (mean_density>fiducial_density):
        Mmin1=Mmin
    else:
        Mmin2=Mmin
    i+=1
print ' '
print 'Mmin=',Mmin
print 'average number of galaxies=',total_galaxies
print 'average galaxy density=',mean_density
#########################################

#take only halos with M>Mmin; the rest do not host central/satellite galaxies
inside=np.where(halo_mass>Mmin)[0]
halo_mass=halo_mass[inside]
halo_pos=halo_pos[inside]
halo_radius=halo_radius[inside]
halo_len=halo_len[inside]
halo_offset=halo_offset[inside]

#compute the number of satellites in each halo using the Poisson distribution 
N_mean_sat=(halo_mass/M1)**alpha #mean number of satellites
N_sat=np.empty(len(N_mean_sat),dtype=np.float32)
for i in range(len(N_sat)):
    N_sat[i]=np.random.poisson(N_mean_sat[i])

print ' '
print np.min(halo_mass),'< M_halo <',np.max(halo_mass)
print 'total number of galaxies=',np.sum(N_sat)+len(halo_mass)
print 'galaxy number density=',(np.sum(N_sat)+len(halo_mass))/(BoxSize*1e-3)**3

#put satellites following the distribution of dark matter in groups
print ' '
print 'Creating mock catalogue ...',
f=open('borrar.dat','w')
index=0
count=0
while (index<halo_mass.size):

    #print halo_pos[index]
    #print halo_radius[index]

    #save the position of the central galaxy
    f.write(str(halo_pos[index,0])+' '+str(halo_pos[index,1])+' '+str(halo_pos[index,2])+'\n')

    #if halo contains satellites, save their positions
    Nsat=N_sat[index]
    if Nsat>0:
        idss=sorted_ids[IDs[halo_offset[index]:halo_offset[index]+halo_len[index]]]
        #compute the radius of those particles and keep those with R<Rvir
        pos=DM_pos[idss]
        posc=pos-halo_pos[index]
        r_max=np.sqrt(posc[:,0]**2+posc[:,1]**2+posc[:,2]**2)
        inside=np.where(r_max<halo_radius[index])[0]
        selected=random.sample(inside,Nsat)
        pos=pos[selected]

        posc=pos-halo_pos[index]
        r_max=np.max(np.sqrt(posc[:,0]**2+posc[:,1]**2+posc[:,2]**2))

        #print 'satellites'
        #print pos
        if r_max>halo_radius[index]:
            print halo_pos[index]
            print halo_radius[index]
            print pos
            count+=1

        for i in range(Nsat):
            f.write(str(pos[i,0])+' '+str(pos[i,1])+' '+str(pos[i,2])+'\n')

    index+=1
f.close()
print 'done'

print 'count = ',count