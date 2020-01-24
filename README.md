# bpftrace + bcc performance analysis tools

## Quick Start

Deploy the pre-built docker image container bpftrace and libbcc to a Kubernetes cluster:

```
kubectl apply -f ./manifests/bpftrace/deploy.yaml
```

Exec into a shell in that pod:
```
kubectl exec -it $(kubectl get pod -o jsonpath="{.items[0].metadata.name}") bash
```

Try out some commands, in this example using Lesson 7 from the [bpftrace one liners][0]:

```
# / bpftrace -e 'kprobe:vfs_read { @start[tid] = nsecs; } kretprobe:vfs_read /@start[tid]/ { @ns[comm] = hist(nsecs - @start[tid]); delete(@start[tid]); }'

Attaching 2 probes...
^C                             

@ns[systemd]:
[2K, 4K)               6 |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@|
[4K, 8K)               6 |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@|
[8K, 16K)              1 |@@@@@@@@                                            |

@ns[iptables]:
[512, 1K)              2 |@@@@@@@@@                                           |
[1K, 2K)              11 |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@|
[2K, 4K)               3 |@@@@@@@@@@@@@@                                      |


@ns[runc]:
[256, 512)             2 |@@@@@@@@@@@                                         |
[512, 1K)              2 |@@@@@@@@@@@                                         |
[1K, 2K)               0 |                                                    |
[2K, 4K)               3 |@@@@@@@@@@@@@@@@@                                   |
[4K, 8K)               1 |@@@@@                                               |
[8K, 16K)              1 |@@@@@                                               |
[16K, 32K)             6 |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                  |
[32K, 64K)             9 |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@|
[64K, 128K)            4 |@@@@@@@@@@@@@@@@@@@@@@@                             |
```

## Reference Information

- one liner tutorials from bpftrace repo: https://github.com/iovisor/bpftrace/blob/master/docs/tutorial_one_liners.md
- language reference: https://github.com/iovisor/bpftrace/blob/master/docs/reference_guide.md
- useful example programs: https://github.com/iovisor/bpftrace/tree/master/tools
- Brendan Gregg has many useful books, articles, and videos/conference talks on bpf and friends.
    - ebpf tools: http://www.brendangregg.com/ebpf.html
    - flamegraphs: http://www.brendangregg.com/FlameGraphs/cpuflamegraphs.html
    - bpf perf tools book (available free online via oreilly): http://www.brendangregg.com/bpf-performance-tools-book.html

## Prometheus Integration

Cloudflare has written a prometheus exporter to execute bcc programs and expose the resulting data as prometheus metrics. This does not yet work against the bpftrace frontend but could be extended in a fairly similar manner. To integrate bcc tooling with prometheus, one needs a cluster with both bpf_exporter and prometheus deployed. There is an example of this deployment pre-packaged in manifests/bpf_exporter, which will deploy kube-prometheus, cert-manager, and the exporter itself. Once everything is deployed, you can view the metrics by port-forwarding the prometheus and grafana services:

```
# each command run in a separate shell, or sent to background.
kubectl -n monitoring port-forward svc/prometheus-k8s 9090
kubectl -n monitoring port-forward svc/grafana 3000
```

Then open up a browser to localhost:3000, logging in using username:password admin:admin.

Create a new grafana dashboard with data source prometheus, querying the metric `ebpf_exporter_bio_latency_seconds_bucket`. Set the type in both the data source and visualization to histogram or heatmap. Leave everything else to auto. The view should end up looking something like this, excepting color scheme:  ![alt text](https://i.imgur.com/VioElst.jpg)


[0]: https://github.com/iovisor/bpftrace/blob/master/docs/tutorial_one_liners.md#lesson-7-timing-reads
