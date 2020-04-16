# Debugging Disk IO

The goal of this document is to provide guidance to debug disk IO problems in Linux. We will use bpftrace and bcc tracing tools, as well as some more traditional tools.

We'll execute this from inside a privileged pod with bpftrace + bcc installed. An example manifest can be found in the root of this repository under manifests/bpftrace/deploy.yaml

These steps may also be performed from a local machine with the tools installed.

## OS Context

IO in Linux passes through a virtual filesystem layer, the actual filesystem, the block device interface, the block layer, and finally the physical device. Filesystems perform caching to decrease latency and increase overall performance.

When devices are saturated we expect to see bimodal distributions in latencies, as requests begin to diverege into those immediately serviceable and those for which we must wait. This is a clear sign of potential issues. This can be observed both at the filesystem layer and at the block layer.

Additionally we want to see a high cache hit rate on the filesystem. A low cache hit rate may be characteristic of the workload, but it's a signal for potential further investigation. We expect to see low cache hit reflected by higher block device output, since that work cannot be served out of cache.

## Baseline

Under normal circumstances on Azure, we generally expect to see latencies on the order of microseconds with premium SSDs. Under load we see latencies on the order of 10ms.

## Approach

- Check filesystem capacity
- Use ext4slower to highlight high latency file system access. Look for bimodal distributions or outliers.
- Use fileslower to track synchronous read/write operations.
- Examine filesystem latency distribution with ext4dist.
- Use cachestat to monitor cache hit ratio, look for dips.
- Manually verify cache hit rate by comparing vfsstat with iostat. The filesystem should see much higher rates than the raw device.
- Use iostat to check for basic IOPS, utilization, and throughput. Ensure these values are below SKU limits.
- Examine block IO latency distributions with biolatency. Look for outliers or bimodal distributions.
- Trace raw block IO with biosnoop and look for latency outliers, or patterns in requests.

### Disk Capacity

High percentages in the Use% column may indicate a problem.

```bash
root@aks-nodepool1-14345218-vmss000003:/$ df -h
Filesystem      Size  Used Avail Use% Mounted on
overlay         993G   15G  979G   2% /
tmpfs            64M     0   64M   0% /dev
tmpfs            63G     0   63G   0% /sys/fs/cgroup
/dev/sda1       993G   15G  979G   2% /usr/src
shm              64M     0   64M   0% /dev/shm
tmpfs            63G   12K   63G   1% /run/secrets/kubernetes.io/serviceaccount
```

These look fairly empty.

### File System Latency

Using ext4slower we can get a high level view of filesystem activity.

The first example is from a system with no activity. The second system has fio running a high queue depth job with 60/40 read/write split. 

We can clearly see a bimodal distribution in the second graph's reads, indicating something may be inducing latency. It's also suspicious that our writes appear to have zero latency while we have high latency reads.

```bash
root@aks-nodepool1-14345218-vmss000003:/# ext4dist-bpfcc  
Tracing ext4 operation latency... Hit Ctrl-C to end.
^C

operation = read
     usecs               : count     distribution
         0 -> 1          : 3599     |****************************************|
         2 -> 3          : 734      |********                                |
         4 -> 7          : 59       |                                        |
         8 -> 15         : 5        |                                        |

operation = write
     usecs               : count     distribution
         0 -> 1          : 12       |********                                |
         2 -> 3          : 57       |****************************************|
         4 -> 7          : 30       |*********************                   |
         8 -> 15         : 22       |***************                         |
        16 -> 31         : 24       |****************                        |
        32 -> 63         : 6        |****                                    |

operation = open
     usecs               : count     distribution
         0 -> 1          : 2323     |****************************************|
         2 -> 3          : 153      |**                                      |
         4 -> 7          : 40       |                                        |
         8 -> 15         : 12       |                                        |
        16 -> 31         : 1        |                                        |
```

```
root@aks-nodepool1-14345218-vmss000003:/# ext4dist-bpfcc
Tracing ext4 operation latency... Hit Ctrl-C to end.
^C

operation = read
     usecs               : count     distribution
         0 -> 1          : 122621   |**********************                  |
         2 -> 3          : 218793   |****************************************|
         4 -> 7          : 6139     |*                                       |
         8 -> 15         : 484      |                                        |
        16 -> 31         : 106      |                                        |
        32 -> 63         : 165      |                                        |
        64 -> 127        : 166726   |******************************          |
       128 -> 255        : 22449    |****                                    |
       256 -> 511        : 466      |                                        |
       512 -> 1023       : 61       |                                        |
      1024 -> 2047       : 13       |                                        |
      2048 -> 4095       : 27       |                                        |
      4096 -> 8191       : 42       |                                        |
      8192 -> 16383      : 641      |                                        |
     16384 -> 32767      : 205      |                                        |
     32768 -> 65535      : 3        |                                        |
     65536 -> 131071     : 1        |                                        |

operation = write
     usecs               : count     distribution
         0 -> 1          : 70       |                                        |
         2 -> 3          : 473952   |****************************************|
         4 -> 7          : 311003   |**************************              |
         8 -> 15         : 14695    |*                                       |
        16 -> 31         : 562      |                                        |
        32 -> 63         : 470      |                                        |
        64 -> 127        : 14       |                                        |
       128 -> 255        : 3        |                                        |
       256 -> 511        : 3        |                                        |

operation = open
     usecs               : count     distribution
         0 -> 1          : 3235     |****************************************|
         2 -> 3          : 174      |**                                      |
         4 -> 7          : 105      |*                                       |
         8 -> 15         : 11       |                                        |
        16 -> 31         : 1        |                                        |
        32 -> 63         : 1        |                                        |
```

#### Finding problematic processes

We can use ext4slower to find specific files where operations hit high latencies.

There would be an example from an unloaded system here, but there should be no output.

```bash
root@aks-nodepool1-14345218-vmss000003:/# ext4slower-bpfcc
Tracing ext4 operations slower than 10 ms
TIME     COMM           PID    T BYTES   OFF_KB   LAT(ms) FILENAME
```

On a loaded system with fio, we immediately see latencies in double digit milliseconds.

```bash
root@aks-nodepool1-14345218-vmss000003:/# ext4slower-bpfcc
Tracing ext4 operations slower than 10 ms
TIME     COMM           PID    T BYTES   OFF_KB   LAT(ms) FILENAME
08:25:12 fio            42393  R 4096    3834404    17.41 test
08:25:12 fio            42394  R 4096    1873144    17.55 test
08:25:12 fio            42394  R 4096    2347836    17.99 test
08:25:12 fio            42393  R 4096    363228     17.93 test
08:25:12 fio            42394  R 4096    1918868    17.76 test
08:25:12 fio            42393  R 4096    2929180    17.79 test
08:25:12 fio            42393  R 4096    2455360    17.35 test
08:25:12 fio            42394  R 4096    977524     17.45 test
08:25:12 fio            42393  R 4096    510232     17.93 test
```

#### Examining cache hit ratio

Cachestat provides output about cache hit percentage, dirty blocks, cache hits, and amount of data read from cache. We generally want to see a high cache hit rate, and also see this reflected in filesystem IO vs disk IO (filesystem IO should be much higher if caching is working).

We provide output for an unloaded and loaded system. On the unloaded system, cache hit rate is a solid 100%. On the loaded system, we see it's 100% before the workload kicks in, and then it plummets to zero. This was a synthetic fio workload with a 60/40 read write mix.

```bash
root@aks-nodepool1-14345218-vmss000003:/# cachestat-bpfcc 
    HITS   MISSES  DIRTIES HITRATIO   BUFFERS_MB  CACHED_MB
      25        0        0  100.00%          391       6793
    4639        0        8  100.00%          391       6793
    3081        0        5  100.00%          391       6793
    6022        0       27  100.00%          391       6793
      29        0        0  100.00%          391       6793
     467        0        8  100.00%          391       6793
    7029        0        0  100.00%          391       6793
```

```bash
root@aks-nodepool1-14345218-vmss000003:/# cachestat-bpfcc 
    HITS   MISSES  DIRTIES HITRATIO   BUFFERS_MB  CACHED_MB
      51        0        0  100.00%          391       4470
    6458       18       27   99.72%          391       4871
     110        0        7  100.00%          391       4871
      66        0        3  100.00%          391       4871
    4517        0       14  100.00%          391       4871
    2728        0        0  100.00%          391       4871
       0        0     2756    0.00%          391       3871
     681     5892    10877   10.36%          391       3936
       0      340    10891    0.00%          391       4001
    2102     5782    10928   26.66%          391       4065
       0     3105    10958    0.00%          391       4130
    3881     5584    11522   41.00%          391       4196
    1093     5044    10145   17.81%          391       4254
       0      452    11199    0.00%          391       4318
       0     5126     9752    0.00%          391       4382
       0     2961     9577    0.00%          391       4447
       0      194     9778    0.00%          391       4513
       0     6917     9881    0.00%          391       4579
       0      431     9324    0.00%          391       4641
       0     7325    10083    0.00%          391       4708
```

We can compare these block IO using iostat and should see the lower cache hit rate reflected as more block IO.

### Block devices

Under load we start spending a significant amount of time in iowait

```bash
root@aks-nodepool1-14345218-vmss000003:/# iostat -ty 1 1
04/16/20 08:36:54
avg-cpu:  %user   %nice %system %iowait  %steal   %idle
           0.06    0.00    0.00    0.00    0.00   99.94

Device             tps    kB_read/s    kB_wrtn/s    kB_dscd/s    kB_read    kB_wrtn    kB_dscd
loop0             0.00         0.00         0.00         0.00          0          0          0
nvme0n1           0.00         0.00         0.00         0.00          0          0          0
nvme1n1           0.00         0.00         0.00         0.00          0          0          0
sda               0.00         0.00         0.00         0.00          0          0          0
sdb               0.00         0.00         0.00         0.00          0          0          0
scd0              0.00         0.00         0.00         0.00          0          0          0
```

```bash
root@aks-nodepool1-14345218-vmss000003:/# iostat -ty 1 1
04/16/20 08:38:19
avg-cpu:  %user   %nice %system %iowait  %steal   %idle
           0.44    0.00    1.26   20.57    0.00   77.73

Device             tps    kB_read/s    kB_wrtn/s    kB_dscd/s    kB_read    kB_wrtn    kB_dscd
loop0             0.00         0.00         0.00         0.00          0          0          0
nvme0n1           0.00         0.00         0.00         0.00          0          0          0
nvme1n1           0.00         0.00         0.00         0.00          0          0          0
sda            8138.00     16164.00     19992.00         0.00      16164      19992          0
sdb               0.00         0.00         0.00         0.00          0          0          0
scd0              0.00         0.00         0.00         0.00          0          0          0
```

Using more detailed output from `iostat -xt`, you'll also see the queue size explode and individual read and write wait times increase under load.

#### Latency

We can use biolatency to identify problems on different disks.

The top chart is an unloaded system. The middle chart is a sytem with fio running against a file on /dev/sda. We see a spike of latencies around the same numbers as the unloaded system, in much higher volume, with a long tail and slightly increase in higher latency.

If we switch fio to direct IO, we will immediately see the latency spike as we get throttled on IOPS. This is third chart.

```bash
root@aks-nodepool1-14345218-vmss000003:/# biolatency-bpfcc -D
Tracing block device I/O... Hit Ctrl-C to end.
^C

disk = b'sda'
     usecs               : count     distribution
         0 -> 1          : 0        |                                        |
         2 -> 3          : 0        |                                        |
         4 -> 7          : 0        |                                        |
         8 -> 15         : 0        |                                        |
        16 -> 31         : 0        |                                        |
        32 -> 63         : 0        |                                        |
        64 -> 127        : 6        |**************                          |
       128 -> 255        : 17       |****************************************|
       256 -> 511        : 1        |**                                      |
       512 -> 1023       : 1        |**                                      |

disk = b''
     usecs               : count     distribution
         0 -> 1          : 0        |                                        |
         2 -> 3          : 0        |                                        |
         4 -> 7          : 0        |                                        |
         8 -> 15         : 0        |                                        |
        16 -> 31         : 0        |                                        |
        32 -> 63         : 0        |                                        |
        64 -> 127        : 0        |                                        |
       128 -> 255        : 0        |                                        |
       256 -> 511        : 0        |                                        |
       512 -> 1023       : 0        |                                        |
      1024 -> 2047       : 0        |                                        |
      2048 -> 4095       : 8        |****************************************|
```

```
disk = b'sda'
     usecs               : count     distribution
         0 -> 1          : 0        |                                        |
         2 -> 3          : 0        |                                        |
         4 -> 7          : 0        |                                        |
         8 -> 15         : 0        |                                        |
        16 -> 31         : 5        |                                        |
        32 -> 63         : 8131     |**                                      |
        64 -> 127        : 151787   |****************************************|
       128 -> 255        : 3655     |                                        |
       256 -> 511        : 339      |                                        |
       512 -> 1023       : 89       |                                        |
      1024 -> 2047       : 25       |                                        |
      2048 -> 4095       : 25       |                                        |
      4096 -> 8191       : 19       |                                        |
      8192 -> 16383      : 348      |                                        |
     16384 -> 32767      : 433      |                                        |
     32768 -> 65535      : 9        |                                        |
     65536 -> 131071     : 7        |                                        |
    131072 -> 262143     : 3        |                                        |

disk = b''
     usecs               : count     distribution
         0 -> 1          : 0        |                                        |
         2 -> 3          : 0        |                                        |
         4 -> 7          : 0        |                                        |
         8 -> 15         : 0        |                                        |
        16 -> 31         : 0        |                                        |
        32 -> 63         : 0        |                                        |
        64 -> 127        : 0        |                                        |
       128 -> 255        : 0        |                                        |
       256 -> 511        : 0        |                                        |
       512 -> 1023       : 0        |                                        |
      1024 -> 2047       : 0        |                                        |
      2048 -> 4095       : 10       |****************************************|
```

```bash
root@aks-nodepool1-14345218-vmss000003:/# biolatency-bpfcc -D
Tracing block device I/O... Hit Ctrl-C to end.
^C

disk = b'sda'
     usecs               : count     distribution
         0 -> 1          : 0        |                                        |
         2 -> 3          : 0        |                                        |
         4 -> 7          : 0        |                                        |
         8 -> 15         : 0        |                                        |
        16 -> 31         : 0        |                                        |
        32 -> 63         : 48       |                                        |
        64 -> 127        : 848      |*                                       |
       128 -> 255        : 3306     |******                                  |
       256 -> 511        : 21078    |****************************************|
       512 -> 1023       : 11887    |**********************                  |
      1024 -> 2047       : 1997     |***                                     |
      2048 -> 4095       : 189      |                                        |
      4096 -> 8191       : 16       |                                        |
      8192 -> 16383      : 9        |                                        |
     16384 -> 32767      : 1        |                                        |
     32768 -> 65535      : 18103    |**********************************      |

disk = b''
     usecs               : count     distribution
         0 -> 1          : 0        |                                        |
         2 -> 3          : 0        |                                        |
         4 -> 7          : 0        |                                        |
         8 -> 15         : 0        |                                        |
        16 -> 31         : 0        |                                        |
        32 -> 63         : 0        |                                        |
        64 -> 127        : 0        |                                        |
       128 -> 255        : 0        |                                        |
       256 -> 511        : 0        |                                        |
       512 -> 1023       : 0        |                                        |
      1024 -> 2047       : 0        |                                        |
      2048 -> 4095       : 3        |****************************************|
```

#### Finding offending processes 

Biosnoop can help find offending processes by pointing out high latency or high frequency operations. Biotop can help in a similar way

Here we have a single system snapshot, before and during a fio run. Latency and queue times both start low, and then latency spikes to 44ms as the disk device gets saturated and throttled.

```bash
root@aks-nodepool1-14345218-vmss000003:/# biosnoop-bpfcc -Q
TIME(s)     COMM           PID    DISK    T SECTOR     BYTES  QUE(ms) LAT(ms)
0.000000    python3        2527   sda     W 5125728    12288     0.01    0.34
0.015997    python3        2527   sda     W 1804936    4096      0.01    0.17
0.032416    python3        2527   sda     W 4284704    4096      0.01    0.18
0.359278    ?              0              R 0          8         0.00    2.89
1.858307    azure-vnet-tel 5230   sda     W 1437456    4096      0.02    0.17
1.858526    azure-vnet-tel 5230   sda     W 1437464    4096      0.00    0.10
2.375276    ?              0              R 0          8         0.00    2.88
3.061376    python3        2527   sda     W 4928568    12288     0.01    0.21
3.076193    python3        2527   sda     W 97019640   4096      0.02    0.11
8.581422    fio            59558  sda     R 22803672   4096      0.00   44.25
8.581443    fio            59558  sda     W 12549992   4096      0.00   44.25
8.581454    fio            59557  sda     W 27036720   4096      0.00   44.25
8.581466    fio            59558  sda     W 18732424   4096      0.00   44.25
8.581477    fio            59557  sda     W 20285376   4096      0.00   44.29
8.581487    fio            59557  sda     R 20208800   4096      0.00   44.27
8.581503    fio            59558  sda     W 16293616   4096      0.00   44.27
8.581520    fio            59557  sda     W 22960736   4096      0.00   44.28
8.581532    fio            59558  sda     W 24036464   4096      0.00   44.27
8.581551    fio            59558  sda     R 27106192   4096      0.00   44.31
8.581576    fio            59557  sda     R 16657568   4096      0.00   44.30
```

biotop can provide similar information and filter only to the top few events, plus refresh on an interval.

```bash
root@aks-nodepool1-14345218-vmss000003:/# biotop-bpfcc
Tracing... Output every 1 secs. Hit Ctrl-C to end
08:04:11 loadavg: 1.48 0.87 0.45 1/287 14547

PID    COMM             D MAJ MIN DISK       I/O  Kbytes  AVGms
14501  cksum            R 202 1   xvda1      361   28832   3.39
6961   dd               R 202 1   xvda1     1628   13024   0.59
13855  dd               R 202 1   xvda1     1627   13016   0.59
326    jbd2/xvda1-8     W 202 1   xvda1        3     168   3.00
```