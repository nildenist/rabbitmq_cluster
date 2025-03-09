const amqp = require('amqplib');

async function startWorker() {
    try {
        // RabbitMQ'ya bağlan
        const connection = await amqp.connect('amqp://localhost');
        const channel = await connection.createChannel();
        const queue = 'test_queue';

        // Kuyruğu oluştur (eğer yoksa)
        await channel.assertQueue(queue, { durable: true });

        // Prefetch ayarı ile mesajları sırayla işle
        channel.prefetch(1);

        console.log("[*] Mesaj bekleniyor. Çıkmak için CTRL+C");

        // Mesajları tüketmeye başla
        channel.consume(queue, (msg) => {
            if (msg !== null) {
                console.log(`[Worker ${process.pid}] Mesaj alındı: ${msg.content.toString()}`);

                // İşlem süresi simülasyonu
                setTimeout(() => {
                    console.log(`[Worker ${process.pid}] İşlem tamamlandı: ${msg.content.toString()}`);
                    channel.ack(msg); // Mesajı onayla
                }, 2000);
            }
        }, { noAck: false });

    } catch (error) {
        console.error("Hata:", error);
    }
}

startWorker();
