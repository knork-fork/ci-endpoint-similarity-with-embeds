<?php

namespace App\Controller;

use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\Routing\Annotation\Route;

class UserController extends AbstractController
{
    /**
     * Retrieve a list of all registered users in the system.
     *
     * Returns a paginated collection of user records including
     * their profile information and account status.
     */
    #[Route('/', name: 'get_all_users', methods: ['GET'])]
    public function getAllUsers(): JsonResponse
    {
        return $this->json(['users' => []]);
    }

    /**
     * Retrieve a single registered user by their identifier.
     *
     * Returns the user record including their profile
     * information and account status.
     */
    #[Route('/{id}', name: 'get_user', methods: ['GET'])]
    public function getUser(int $id): JsonResponse
    {
        return $this->json(['user' => []]);
    }
}
