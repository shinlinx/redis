# Initialization tests -- most units will start including this.

proc restart_killed_instances {} {
    foreach type {redis sentinel} {
        foreach_${type}_id id {
            if {[get_instance_attrib $type $id pid] == -1} {
                puts -nonewline "$type/$id "
                flush stdout
                restart_instance $type $id
            }
        }
    }
}

proc verify_sentinel_auto_discovery {} {
    set sentinels [llength $::sentinel_instances]
    foreach_sentinel_id id {
        wait_for_condition 1000 50 {
            [dict get [S $id SENTINEL MASTER mymaster] num-other-sentinels] == ($sentinels-1)
        } else {
            fail "At least some sentinel can't detect some other sentinel"
        }
    }
}

test "(init) Restart killed instances" {
    restart_killed_instances
}

test "(init) Remove old master entry from sentinels" {
    foreach_sentinel_id id {
        catch {S $id SENTINEL REMOVE mymaster}
    }
}

set redis_slaves [expr $::instances_count - 1]
test "(init) Create a master-slaves cluster of [expr $redis_slaves+1] instances" {
    create_redis_master_slave_cluster [expr {$redis_slaves+1}]
}
set master_id 0

test "(init) Sentinels can start monitoring a master" {
    set sentinels [llength $::sentinel_instances]
    set quorum [expr {$sentinels/2+1}]
    foreach_sentinel_id id {
        S $id SENTINEL MONITOR mymaster \
              [get_instance_attrib redis $master_id host] \
              [get_instance_attrib redis $master_id port] $quorum
    }
    foreach_sentinel_id id {
        assert {[S $id sentinel master mymaster] ne {}}
        S $id SENTINEL SET mymaster down-after-milliseconds 2000
        S $id SENTINEL SET mymaster failover-timeout 20000
        S $id SENTINEL SET mymaster parallel-syncs 10
        if {$::leaked_fds_file != "" && [exec uname] == "Linux"} {
            S $id SENTINEL SET mymaster notification-script ../../tests/helpers/check_leaked_fds.tcl
            S $id SENTINEL SET mymaster client-reconfig-script ../../tests/helpers/check_leaked_fds.tcl
        }
    }
}

test "(init) Sentinels can talk with the master" {
    foreach_sentinel_id id {
        wait_for_condition 1000 50 {
            [catch {S $id SENTINEL GET-MASTER-ADDR-BY-NAME mymaster}] == 0
        } else {
            fail "Sentinel $id can't talk with the master."
        }
    }
}

test "(init) Sentinels are able to auto-discover other sentinels" {
    verify_sentinel_auto_discovery
}

test "(init) Sentinels are able to auto-discover slaves" {
    foreach_sentinel_id id {
        wait_for_condition 1000 50 {
            [dict get [S $id SENTINEL MASTER mymaster] num-slaves] == $redis_slaves
        } else {
            fail "At least some sentinel can't detect some slave"
        }
    }
}
