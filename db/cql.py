#!/usr/bin/python3
from paramiko import SSHClient, AutoAddPolicy
import sshtunnel
import time
import argparse
from pprint import pprint

from cassandra import ConsistencyLevel, DriverException, InvalidRequest
from cassandra.cluster import Cluster, BatchStatement
from cassandra.query import SimpleStatement, dict_factory
from cassandra.auth import PlainTextAuthProvider
from cassandra.concurrent import execute_concurrent_with_args
from cassandra.protocol import SyntaxException

trace = True
def DEBUG(*msg):
    if trace:
        print(*msg)

class CassandraClient():
    def __init__(self, cluster_ips, port=9042, user=None, password=None):
        DEBUG('Create Cluster:', cluster_ips, port, user, password)
        self.user = user
        self.password = password
        self.port = port
        self.ips = cluster_ips
        self.credential = PlainTextAuthProvider(username=self.user, password=self.password)
        self.cluster = Cluster(self.ips, port=self.port, auth_provider=self.credential)
        self.session = None

    def create_session(self, keyspace=None):
        if not self.session:
            try:
                self.session = self.cluster.connect(keyspace)
                self.session.row_factory = dict_factory
            except DriverException as e:
                DEBUG('Failed to connect Cluster:', e)
                if 'Cluster is already shut down' in e:
                    self.cluster = Cluster(self.ips, port=self.port, auth_provider=self.credential)
                    self.create_session(keyspace)

    def exec(self, query, size=None, paging_state=None):
        DEBUG('Send query:', query, size, paging_state)
        statement = SimpleStatement(query, fetch_size=size)
        rows = self.session.execute(statement, paging_state=paging_state)
        DEBUG('Response paging:', rows.paging_state)
        return rows

    def exec_async(self, query):
        result = self.session.execute_async(query)
        return result

    def close(self):
        DEBUG('Close Cluster:', self.ips, self.port, self.user, self.password)
        self.cluster.shutdown()

class Remote():
    def __init__(self, host, user, password):
        self.host = host
        self.user = user
        self.passwd = password
        self.tunnel = None
        self.ssh = None

    def connect(self, service_host, port):
        DEBUG('Create ssh tunnel:', self.user, self.passwd, self.host, 'bind:', service_host, port)
        self.tunnel = sshtunnel.open_tunnel(
            self.host, ssh_username=self.user, ssh_password=self.passwd,
            remote_bind_address=(service_host, port),
            set_keepalive=0.5,
            #debug_level='TRACE'
            )
        return self.tunnel

    def start(self):
        self.tunnel.start()

    def stop(self):
        DEBUG('Close ssh tunnel:', self.user, self.passwd, self.host)
        self.tunnel.stop()

    def local_port(self):
        return self.tunnel.local_bind_port

    def cmd(self, cmd_str):
        with SSHClient() as ssh:
            ssh.load_system_host_keys()
            ssh.set_missing_host_key_policy(AutoAddPolicy())
            ssh.connect(self.host)
            stdin, stdout, stderr = ssh.exec_command(cmd_str)
            out = stdout.read().decode()
            err = stderr.read().decode()
        return out, err

class Query():
    def __init__(self, cass_ips, port, user, password, debug=None):
        self.cass_ips = cass_ips.split(',')
        self.port = int(port)
        self.user = user
        self.password = password
        self.size = 50
        self.cql = None
        self.ssh = None
        self.paging_state = None
        self.db = None
        if debug is not None:
            global trace
            trace = debug

    def open(self, host, user, password):
        if self.ssh:
            return
        try:
            self.ssh = Remote(host, user, password)
            # ssh to host to get cassandra IP
            self.detect_db_ip()
            # setup ssh tunnel
            self.ssh.connect(self.cass_ips[0], self.port)
            self.ssh.start()
            self.port = self.ssh.local_port()
            self.cass_ips = ['127.0.0.1']
        except Exception as e:
            self.ssh = None
            raise e

    def close(self):
        if self.db:
            self.db.close()
            self.db = None
        if self.ssh:
            self.ssh.stop()
            self.ssh = None

    def query(self, cql, paging=None, limit=None, sync=True):
        self.cql = cql
        if not self.db:
            self.db = CassandraClient(self.cass_ips, self.port, self.user, self.password)
        self.db.create_session()
        tm = time.time()
        if limit is None:
            limit = self.size
        try:
            if sync:
                rows = self.db.exec(cql, size=limit, paging_state=paging)
            else:
                rows = self.db.exec_async(cql)
        except (InvalidRequest, SyntaxException) as e:
            print(e)
            return e, None, 0, None
        return 'ok', rows.current_rows, time.time() - tm, rows.paging_state

    def query_concurrent(self, statement, params, num=50):
        self.cql = SimpleStatement(statement)
        DEBUG('Send query:', self.cql, params)
        if not self.db:
            self.db = CassandraClient(self.cass_ips, self.port, self.user, self.password)
        self.db.create_session()
        tm = time.time()
        self.cql = self.db.session.prepare(statement)
        rows = execute_concurrent_with_args(self.db.session, self.cql, params, concurrency=num)
        return rows.current_rows, time.time() - tm, rows.paging_state

    def detect_db_ip(self):
        ip, _ = self.ssh.cmd("ss -4ntl | grep :9042 | awk '{print $4}'")
        if ip:
           self.cass_ips = []
           self.cass_ips.append(ip.split(':')[0])
        DEBUG('Cassandra IP is', self.cass_ips)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('-r', '--remote', action='store_true', help='SSH to remote host')
    parser.add_argument('-u', '--remote-user', help='SSH user')
    parser.add_argument('-p', '--remote-password', help='SSH Password')

    parser.add_argument('--ip', required=True, help='Cassandra Listen IP or Remote Host IP')
    parser.add_argument('--port', help='Cassandra Listen Port, default 9042')
    parser.add_argument('--user', help='Cassandra User')
    parser.add_argument('--passwd', help='Cassandra Password')
    parser.add_argument('--cql', help='Cassandra Query String')
    parser.add_argument('--keyspaces', action='store_true', help='List Cassandra keyspaces')
    parser.add_argument('--tables', action='store_true', help='List All Cassandra keyspaces and tables')
    parser.add_argument('-c', '--continues', action='store_true', help='Display all result without prompt')
    parser.add_argument('--debug', action='store_true', help='Print debug message')

    args = parser.parse_args()

    cass_user = args.user
    cass_passwd = args.passwd
    if not args.user and not args.passwd:
        cass_user = 'sdn'
        cass_passwd = 'sdncassandra'
    port = 9042
    if args.port:
        port = args.port
    q = Query(args.ip, port, cass_user, cass_passwd, args.debug)

    if args.remote:
        password = args.remote_password
        if not password:
            password = input('Password: ')
        user = 'root'
        if args.remote_user:
            user = args.remote_user
        q.open(args.ip, user, password)

    def tables(table=None):
        if table:
            return 'SELECT * FROM system_schema.tables WHERE table_name = %s' % table
        return 'SELECT keyspace_name, table_name FROM system_schema.tables'
    def keyspaces(keyspace=None):
        if keyspace:
            return 'SELECT * FROM system_schema.keyspaces WHERE keyspace_name = %s' % keyspace
        return 'SELECT * FROM system_schema.keyspaces'

    cql = args.cql
    if args.keyspaces:
        cql = keyspaces()
    if args.tables:
        cql = tables()

    def execute_cql(cql, ignore_sys=False):
        tm_total = 0
        try:
            _, rows, tm, page = q.query(cql)
            tm_total += tm
            while rows:
                num = 0
                for row in rows:
                    num +=1
                    if ignore_sys and row['keyspace_name'].startswith('system'):
                        continue
                    print(num)
                    pprint(row)
                if not page:
                    break
                if not args.continues:
                    input('----more----')
                _, rows, tm, page = q.query(cql, page)
                tm_total += tm
        except KeyboardInterrupt as e:
            pass
        return tm_total
    if cql:
        tm = execute_cql(cql)
        print('\nTotal Time:', tm)
    else:
        cql = input('cql> ')
        while cql != 'quit' and cql != 'exit':
            if cql:
                ignore_sys = False
                if cql.startswith('desc'):
                    cmd = cql.split()
                    if cmd[1] == 'tables':
                        cql = tables()
                        ignore_sys = True
                    elif cmd[1] == 'keyspaces':
                        cql = keyspaces()
                        ignore_sys = True
                    elif cmd[1] == 'table':
                        if len(cmd) < 3:
                            print('Error: Missing table name')
                        else:
                            cql = tables(cmd[2])
                    elif cmd[1] == 'keyspace':
                        if len(cmd) < 3:
                            print('Error: Missing table name')
                        else:
                            cql = keyspaces(cmd[2])
                execute_cql(cql, ignore_sys)
            cql = input('cql> ')
    q.close()

if __name__ == '__main__':
    main()
