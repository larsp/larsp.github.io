+++
date = "2018-12-05T20:00:00-01:00"
draft = false
title = "Distributed Worker Queues - A piece of Cake🍰"
tags = ["MySQL", "Programming", "Distributed Systems", "Software Development"]
authors = ["Lars"]
+++

![Photo by Trevor Cole on Unsplash](/img/queue.webp)

*This post was originally published on [medium](https://medium.com/yoyo-labs/distributed-worker-queues-a-piece-of-cake-fe1a7356e156) in December 2018. I've republished it here as part of consolidating my writing on this blog. The original content remains unchanged except for minor formatting adjustments.*


Distributed Worker Queues are a valuable decoupling mechanism for various use-cases in software & systems engineering:

*   Decoupling of job production and job consumption, e.g. for tasks where human interaction is needed.
*   Minimize latencies in user facing systems by moving resource intensive tasks to a designated set of machines, e.g. for video encoding.
*   Purpose-built computational resources are required for a specific task, e.g. using GPUs to train a machine learning model.

Enter a database-backed distributed worker queue mechanism that is easy to test, deploy, and maintain, as well as reliable and cheap.

### MySQL for a Distributed Worker Queue?

MySQL v8.0.1 [introduced](https://dev.mysql.com/doc/refman/8.0/en/innodb-locking-reads.html#innodb-locking-reads-nowait-skip-locked) (finally 🥳) a `SKIP LOCKED` option to `SELECT … FOR UPDATE` and `SELECT … FOR SHARE` statements. Thus, a locking `FOR UPDATE` read that leverages the new `SKIP LOCKED` option will not wait to acquire a row lock, but instead, will simply ignore locked rows in the result.

Combined with transactions this becomes a handy feature to implement a simple, reliable and efficient distributed worker queue. Let’s dive into a possible solution.

### Table Schema

```mysql
CREATE TABLE IF NOT EXISTS worker_queue
(
    id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    command TEXT NOT NULL,
    is_done BOOLEAN NOT NULL DEFAULT FALSE,
    failure_count SMALLINT DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=UTF8MB4;
```

We are going to introduce an auto-increment `id` field. As follows, sorting in ascending or descending order on the `id` field will enable either _FIFO_ or _LIFO_ queue characteristics. In the given example the `command` is a simple text field, but it could be anything fitting your needs. In order to be able to indicate that a specific message in the queue has been processed the `is_done` field is introduced. Even retry and maximum retry capabilities can be realized through a simple `failure_count`.

### Adding a Message

Adding a new message is literally as simple as an `INSERT` into a table.

```mysql
INSERT INTO worker_queue (command) VALUES (‘do this’);
```

### Retrieve & Lock a Message

```mysql
START TRANSACTION;SELECT id, command FROM worker_queue
WHERE failure_count < 3
AND is_done = FALSE
ORDER BY id
LIMIT 1
FOR UPDATE SKIP LOCKED;
```

A worker process will start a transaction which will stay open until the corresponding work is done. In our case we sort by `id` in ascending order to implement a FIFO. The given query will read and obtain a read-lock for one row, this keeps other worker instances from processing the message simultaneously. The query also filters rows which are currently locked using the newly introduced `SKIP LOCKED` option. Additionally `failure_count < 3` will filter for rows which have not been consumed and failed for more than three times. We will cover this in more detail shortly. Once a lock is obtained, we can start processing the respective message. In case a worker process dies, the lock for a given message will be released automatically since the lock was obtained in a not yet committed transaction. This way the message will be available for consumption again.

### Acknowledge a Message

To acknowledge that a message has been processed, `is_done` has to be set to `true` as final statement of the current transaction.

```mysql
UPDATE worker_queue
SET is_done = TRUE
WHERE id = <id>;COMMIT;
```

### Graceful Failure & Maximum Retries

Dead Letter Queue behavior can be achieved through the previously introduced `failure_count`. When a failure count for a message exceeds a certain threshold it will no longer be returned from the earlier query. A separate worker process which obtains such elements will help analyze and understand why messages are failing.

```mysql
UPDATE worker_queue
SET is_done = FALSE, failure_count = failure_count + 1
WHERE id = <id>;
COMMIT;
```

### Cleaning up

Since we are filling up the worker queue table with messages it is desirable to periodically clean up completed or faulty tasks. This could be accomplished through a simple delete:

```mysql
DELETE FROM worker_queue
WHERE is_done = TRUE
OR failure_count >= 3;
```

If the history or an archive is needed, messages could be moved to different tables instead. MySQL’s [Event Scheduler](https://dev.mysql.com/doc/refman/8.0/en/event-scheduler.html) could be used to implement periodic query execution.

### Conclusions

Dozens of strategies and technologies exist for implementing a distributed worker queue. If you favor PostgreSQL for example, you could use the same strategy as of version 9.5.

Using the database’s internal lock mechanism has some advantages:

*   **MySQL is extremely common**. Almost everyone has a MySQL or PostgreSQL installation up and running somewhere. If not, it is **straightforward** to set up. If you don’t want to deal with the setup yourself you could use **managed services** e.g. from any of the top cloud providers.
*   Since we are using MySQL internal locking, producer and consumer are **language agnostic**. All you need is a database driver in the programming language of your choice. Furthermore, in a heterogeneous environment where consumer processes are implemented in different languages, using a standard database for coordination can become the lingua franca of your distributed workers.

Without a doubt, this approach is not made for “web scale” type of workloads. Nonetheless, since we are using database internal locking mechanisms, the **throughput is high enough for a large class of workloads** with hundreds or thousands of work items per second.