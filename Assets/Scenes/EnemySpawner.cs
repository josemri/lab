using UnityEngine;

public class EnemySpawner : MonoBehaviour
{
    public GameObject enemyPrefab;

    public Transform player;

    public float spawnRadius = 20f;

    public float spawnInterval = 2f;

    void Start()
    {
        InvokeRepeating(nameof(SpawnEnemy), 1f, spawnInterval);
    }

    void SpawnEnemy()
    {
        Vector2 randomCircle = Random.insideUnitCircle.normalized;
        Vector3 randomDirection = new Vector3(randomCircle.x, 0f, randomCircle.y);

        Vector3 spawnPosition = player.position + randomDirection * spawnRadius;

        GameObject enemy = Instantiate(enemyPrefab, spawnPosition, Quaternion.identity);

        enemy.GetComponent<EnemyMovement>().target = player;
    }
}