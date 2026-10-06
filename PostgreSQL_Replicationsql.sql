PostgreSQL 17 physical streaming replication setup for Primary → Standby


Primary Server IP: 192.168.1.101
Secondry Server IP:192.168.1.102

IF any changes done in PostgreSQL Config then dont restart services (Use Below CMD)
--SELECT pg_reload_conf();


1) Check PostgreSQL 17
Run on both servers:
--select version();

Check Serverice is running 
--sudo systemctl status postgresql

Check cluster:
--pg_lsclusters

2) Primary Server IP (192.168.1.101)  Configuration:
Connect to PostgreSQL:
--sudo -u postgres psql

Create replication user:
--psql
CREATE ROLE replicator
WITH REPLICATION
LOGIN
PASSWORD 'ReplicationPassword';

Check for user is create or not 
\du replicator

3) Configure postgresql.conf -- set on primary Sever
 
--sudo -u postgres psql -c "SHOW config_file;"
--/etc/postgresql/17/main/postgresql.conf
--sudo nano /etc/postgresql/17/main/postgresql.conf

listen_addresses = '*'
port = 5432

wal_level = replica

max_wal_senders = 10
max_replication_slots = 10

wal_keep_size = 2048MB

hot_standby = on

archive_mode = on
archive_command = 'test ! -f /var/lib/postgresql/17/archive/%f && cp %p /var/lib/postgresql/17/archive/%f'

password_encryption = 'scram-sha-256'

Create archive directory:
--sudo mkdir -p /var/lib/postgresql/17/archive
--sudo chown postgres:postgres /var/lib/postgresql/17/archive
--sudo chmod 700 /var/lib/postgresql/17/archive

4. Configure pg_hba.conf --Primary Server 

--sudo -u postgres psql -c "SHOW hba_file;"
--sudo nano /etc/postgresql/17/main/pg_hba.conf
host    replication    replicator    192.168.42.102/32    scram-sha-256   --192.168.1.102 -- Secondry Server Ip 

**If you also want normal database access from standby:
host    all             all           192.168.42.102/32    scram-sha-256

5) Restart Primary Server 
--sudo systemctl restart postgresql
--sudo systemctl status postgresql

Verify Setting 
--sudo -u postgres psql -c "SHOW wal_level;"
--sudo -u postgres psql -c "SHOW max_wal_senders;"
--sudo -u postgres psql -c "SHOW max_replication_slots;"

****
PostgreSQL 17 physical streaming replication, the secondary/standby Windows server also 
needs a few settings, but the configuration is different from the Primary.***

1)Secondary postgresql.conf
On the Secondary, the important settings are:

listen_addresses = '*'
port = 5432

hot_standby = on

2)The Secondarys pg_hba.conf only needs rules if you want applications/users to connect to the standby.
For example:
host    all    all    192.168.1.0/24    scram-sha-256

3)Secondary needs standby.signal

This is very important.
After pg_basebackup, PostgreSQL 17 Standby should have:
C:\Program Files\PostgreSQL\17\data\standby.signal

4)Secondary needs primary_conninfo
Check:
Get-Content "C:\Program Files\PostgreSQL\17\data\postgresql.auto.conf"


6) Test Replication Connection 
From Standby: TO Connect Primary Server 
--psql -h 192.168.42.101 -U replicator -d postgres
Enter replication password.== 'ReplicationPassword'

7)  Create Replication Slot
On Primary:
--"C:\Program Files\PostgreSQL\17\bin\psql.exe" -U postgres    //In Windows Server 
--sudo -u postgres psql 
--SELECT pg_create_physical_replication_slot('standby_slot');

Check :

SELECT slot_name,
       slot_type,
       active,
       restart_lsn
FROM pg_replication_slots;

--Output like this 
 --standby_slot | physical | f
 
8) Check PostgreSQL Port
Run: 
--netstat -ano | findstr :5432

--OutPut Like this 
TCP    192.168.42.101:5432    0.0.0.0:0    LISTENING

9) Windows Firewall
Run PowerShell as Administrator: (PRIMARY Server)
New-NetFirewallRule `
    -DisplayName "PostgreSQL 17 Replication" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 5432 `
    -RemoteAddress 192.168.42.102 `
    -Action Allow


10) Test from the Standby machine
On the 192.168.1.103 machine, run:
Test-NetConnection -ComputerName <PRIMARY_IP> -Port 5432

For example, if your Primary is 192.168.1.100:
Test-NetConnection -ComputerName 192.168.1.100 -Port 5432

--You want Output:
TcpTestSucceeded : True


11) Take Base Backup from Primary

sudo -u postgres pg_basebackup \
-h 192.168.42.101 \
-p 5432 \
-D /var/lib/postgresql/17/main \
-U replicator \
-P \
-R \
-X stream \
-S standby_slot

A) after take base backup from primry then  check on Secondry server 
sudo ls -l /var/lib/postgresql/17/main/standby.signal
** standby.signal

--sudo grep primary_conninfo /var/lib/postgresql/17/main/postgresql.auto.conf

12) Start Standby(Secondry Server)
--sudo systemctl start postgresql
--sudo systemctl status postgresql

13) Check Standby Recovery
On Standby:

--sudo -u postgres psql -c "SELECT pg_is_in_recovery();"
Expected O/P:
 pg_is_in_recovery
-------------------
 t
-- t means the server is running as a standby.

14) Check Primary Replication
On Primary:
--Connect DB 
--sudo -u postgres psql

SELECT
    pid,
    usename,
    application_name,
    client_addr,
    state,
    sync_state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn
FROM pg_stat_replication;

--You should see:
state      | streaming
sync_state | async


15) Better Replication Monitoring Query
On Primary:

SELECT
    application_name,
    client_addr,
    state,
    sync_state,
    pg_size_pretty(
        pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)
    ) AS replication_lag
FROM pg_stat_replication;

--Outpout Like this
application_name |   client_addr    |   state    | sync_state | replication_lag
------------------+------------------+------------+------------+----------------
 17/main          | 192.168.42.102    | streaming  | async      | 0 bytes
 
 16) Check Replication Slot
Primary:
SELECT
    slot_name,
    slot_type,
    active,
    restart_lsn,
    confirmed_flush_lsn
FROM pg_replication_slots;

--For physical replication: Output Like this 
standby_slot | physical | t
--t for active means the standby is connected.

17) Check WAL Receiver on Standby
On Standby:
SELECT
    status,
    receive_start_lsn,
    written_lsn,
    flushed_lsn,
    latest_end_lsn,
    sender_host,
    sender_port
FROM pg_stat_wal_receiver;

--Expected OutPut 
status
---------
streaming