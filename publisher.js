const amqp = require('amqplib');

async function publishMessages() {
    try {
        // RabbitMQ'ya bağlan
        const connection = await amqp.connect('amqp://10.128.0.37');
        const channel = await connection.createChannel();
        const queue = 'test_queue';

        // Kuyruğu oluştur (eğer yoksa)
        await channel.assertQueue(queue, { durable: true });

        // 10 mesaj gönderelim
        for (let i = 1; i <= 10; i++) {
            const message = `Test mesajı ${i}`;
            channel.sendToQueue(queue, Buffer.from(message), { persistent: true });
            console.log(`[x] Gönderildi: ${message}`);
            await new Promise(resolve => setTimeout(resolve, 1000)); // 1 saniye bekle
        }

        setTimeout(() => {
            connection.close();
            process.exit(0);
        }, 500);
    } catch (error) {
        console.error("Hata:", error);
    }
}

publishMessages();
