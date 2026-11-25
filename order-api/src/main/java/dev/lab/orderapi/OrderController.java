package dev.lab.orderapi;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Positive;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.Collection;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/orders")
public class OrderController {

    public record CreateOrder(
            @NotBlank String customer, @Positive BigDecimal amount) {}

    public record Order(long id, String customer, BigDecimal amount, String status, Instant createdAt) {}

    // In-memory for now; persistence and messaging arrive in step #2.
    private final Map<Long, Order> orders = new ConcurrentHashMap<>();
    private final AtomicLong seq = new AtomicLong();

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Order create(@Valid @RequestBody CreateOrder in) {
        var order = new Order(seq.incrementAndGet(), in.customer(), in.amount(), "CREATED", Instant.now());
        orders.put(order.id(), order);
        return order;
    }

    @GetMapping
    public Collection<Order> list() {
        return orders.values();
    }
}
